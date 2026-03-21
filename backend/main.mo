import Liminal "mo:liminal";
import RouterMiddleware "mo:liminal/Middleware/Router";
import Router "mo:liminal/Router";
import IcpLedger "IcpLedger";
import UrlRouter "UrlRouter";
import UrlStore "UrlStore";
import BTree "mo:stableheapbtreemap/BTree";
import Principal "mo:core@1/Principal";
import Runtime "mo:core@1/Runtime";
import Result "mo:core@1/Result";
import Blob "mo:core@1/Blob";
import Text "mo:core@1/Text";
import Debug "mo:core@1/Debug";
import Iter "mo:core@1/Iter";
import Char "mo:core@1/Char";
import Nat "mo:core@1/Nat";
import Nat64 "mo:core@1/Nat64";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import ExperimentalCycles "mo:base/ExperimentalCycles";

shared ({ caller = initializer }) persistent actor class Actor() = self {
  type HeaderField = (Text, Text);
  type HttpRequestArgs = {
    url : Text;
    max_response_bytes : ?Nat64;
    headers : [HeaderField];
    body : ?Blob;
    method : { #get; #head; #post };
    transform : ?TransformContext;
  };
  type HttpResponsePayload = {
    status : Nat;
    headers : [HeaderField];
    body : Blob;
  };
  type TransformContext = {
    function : shared query TransformArgs -> async HttpResponsePayload;
    context : Blob;
  };
  type TransformArgs = { response : HttpResponsePayload; context : Blob };

  let ic : actor {
    http_request : HttpRequestArgs -> async HttpResponsePayload;
  } = actor ("aaaaa-aa");

  var urlStableData : UrlStore.StableData = {
    urls = BTree.init<Nat, UrlStore.Url>(null);
    nextId = 1;
  };

  transient var urlStore = UrlStore.Store(urlStableData);
  transient let canisterPrincipal = Principal.fromActor(self);
  transient var urlRouter = UrlRouter.Router(urlStore, Principal.toText(canisterPrincipal) # ".icp0.io");

  system func preupgrade() {
    urlStableData := urlStore.toStableData();
  };

  system func postupgrade() {
    urlStore := UrlStore.Store(urlStableData);
    urlRouter := UrlRouter.Router(urlStore, Principal.toText(canisterPrincipal) # ".icp0.io");
    routerConfig := buildRouterConfig();
    app := buildApp(routerConfig);
  };

  public shared query ({ caller }) func list_my_urls() : async [UrlStore.UrlView] {
    assertAuthenticated(caller);
    urlStore.getUrlsByOwner(caller);
  };

  public shared ({ caller }) func get_wallet_info() : async IcpLedger.WalletInfo {
    assertAuthenticated(caller);
    await IcpLedger.getWalletInfo(canisterPrincipal, caller);
  };

  public shared ({ caller }) func create_my_url(request : UrlStore.CreateRequest) : async Result.Result<UrlStore.UrlView, Text> {
    assertAuthenticated(caller);

    switch (urlStore.validateCreateRequest(request)) {
      case (#err(message)) {
        return #err(message);
      };
      case (#ok(())) {};
    };

    switch (await IcpLedger.chargeForUrl(canisterPrincipal, caller)) {
      case (#err(message)) {
        #err("Payment required before Tiny ICP can create your short URL. " # message);
      };
      case (#ok(())) {
        let metadata = await fetchUrlMetadata(request.originalUrl);
        switch (urlStore.create(request, caller, metadata)) {
          case (#ok(url)) #ok(urlStore.toView(url));
          case (#err(message)) #err(message);
        };
      };
    };
  };

  public shared ({ caller }) func delete_my_url(id : Nat) : async Result.Result<(), Text> {
    assertAuthenticated(caller);
    urlStore.delete(id, caller);
  };

  public shared ({ caller }) func refresh_my_url_metadata(id : Nat) : async Result.Result<UrlStore.UrlView, Text> {
    assertAuthenticated(caller);

    let ?url = urlStore.getUrlById(id) else return #err("URL not found");
    if (not Principal.equal(url.owner, caller)) {
      return #err("You can only refresh URLs you created");
    };

    let ?metadata = await fetchUrlMetadata(url.originalUrl) else {
      return #err(
        "TinyICP could not extract preview metadata from " # url.originalUrl #
        ". The destination page may be blocking canister HTTPS outcalls or missing Open Graph and Twitter card tags."
      );
    };

    switch (urlStore.updateMetadata(id, caller, ?metadata)) {
      case (#ok(updatedUrl)) #ok(urlStore.toView(updatedUrl));
      case (#err(message)) #err(message);
    };
  };

  public shared ({ caller }) func save_my_url_metadata(
    id : Nat,
    metadata : UrlStore.UrlMetadata,
  ) : async Result.Result<UrlStore.UrlView, Text> {
    assertAuthenticated(caller);

    if (not hasUsefulMetadata(?metadata)) {
      return #err("Preview metadata payload is empty");
    };

    switch (urlStore.updateMetadata(id, caller, ?metadata)) {
      case (#ok(updatedUrl)) #ok(urlStore.toView(updatedUrl));
      case (#err(message)) #err(message);
    };
  };

  public shared ({ caller }) func refresh_all_missing_metadata() : async Result.Result<Nat, Text> {
    assertInstaller(caller);

    let urls = urlStore.getUrlsMissingMetadata();
    var refreshed = 0;

    for (url in urls.vals()) {
      switch (await fetchUrlMetadata(url.originalUrl)) {
        case (?metadata) {
          switch (urlStore.replaceMetadata(url.id, ?metadata)) {
            case (#ok(_)) {
              refreshed += 1;
            };
            case (#err(message)) {
              return #err(message);
            };
          };
        };
        case null {
          Debug.print("Skipping preview backfill for " # url.originalUrl # " because no useful metadata was returned");
        };
      };
    };

    #ok(refreshed);
  };

  public shared ({ caller }) func withdraw_from_wallet(destinationAccountId : Text, amountE8s : Nat) : async Result.Result<(), Text> {
    assertAuthenticated(caller);
    await IcpLedger.withdrawFromWallet(canisterPrincipal, caller, destinationAccountId, amountE8s);
  };

  public shared query ({ caller }) func whoami() : async Principal {
    caller;
  };

  public query func transformPreviewMetadata(args : TransformArgs) : async HttpResponsePayload {
    let empty = emptyMetadata();
    let serializedBody = Text.encodeUtf8(serializeMetadata(empty));

    if (args.response.status < 200 or args.response.status >= 400) {
      return {
        status = args.response.status;
        headers = [("content-type", "text/plain; charset=utf-8")];
        body = serializedBody;
      };
    };

    let ?originalUrl = Text.decodeUtf8(args.context) else {
      return {
        status = 200;
        headers = [("content-type", "text/plain; charset=utf-8")];
        body = serializedBody;
      };
    };

    let ?html = Text.decodeUtf8(args.response.body) else {
      return {
        status = 200;
        headers = [("content-type", "text/plain; charset=utf-8")];
        body = serializedBody;
      };
    };

    {
      status = 200;
      headers = [("content-type", "text/plain; charset=utf-8")];
      body = Text.encodeUtf8(serializeMetadata(extractMetadata(html, originalUrl)));
    };
  };

  func assertAuthenticated(caller : Principal) {
    if (Principal.isAnonymous(caller)) {
      Runtime.trap("Authentication required");
    };
  };

  func assertInstaller(caller : Principal) {
    if (not Principal.equal(caller, initializer)) {
      Runtime.trap("Only the canister installer can run this maintenance method");
    };
  };

  func buildRouterConfig() : RouterMiddleware.Config {
    {
      prefix = null;
      identityRequirement = null;
      routes = [
        Router.getUpdate("/s/{shortCode}", urlRouter.redirect),
        Router.getQuery("/s/{shortCode}/stats", urlRouter.getStats),
      ];
    };
  };

  func buildApp(config : RouterMiddleware.Config) : Liminal.App {
    Liminal.App({
      middleware = [RouterMiddleware.new(config)];
      errorSerializer = Liminal.defaultJsonErrorSerializer;
      candidRepresentationNegotiator = Liminal.defaultCandidRepresentationNegotiator;
      logger = Liminal.buildDebugLogger(#info);
    });
  };

  func fetchUrlMetadata(originalUrl : Text) : async ?UrlStore.UrlMetadata {
    if (not Text.startsWith(originalUrl, #text("https://"))) {
      return null;
    };

    for (requestUrl in previewSourceUrls(originalUrl).vals()) {
      switch (await fetchUrlMetadataOnce(requestUrl, originalUrl)) {
        case (?metadata) {
          if (requestUrl != originalUrl) {
            Debug.print("Preview metadata fetch succeeded via fallback source " # requestUrl # " for " # originalUrl);
          };
          return ?metadata;
        };
        case null {};
      };
    };

    null;
  };

  func fetchUrlMetadataOnce(requestUrl : Text, originalUrl : Text) : async ?UrlStore.UrlMetadata {
    if (not Text.startsWith(requestUrl, #text("https://"))) {
      return null;
    };

    let request : HttpRequestArgs = {
      url = requestUrl;
      max_response_bytes = ?250_000;
      headers = [
        (
          "User-Agent",
          "Mozilla/5.0 (compatible; TinyICPPreviewBot/1.0; +https://tinyicp.app/preview-bot)"
        ),
        ("Accept", "text/html,application/xhtml+xml"),
        ("Accept-Language", "en-US,en;q=0.9"),
        ("Accept-Encoding", "identity"),
      ];
      body = null;
      method = #get;
      transform = ?{
        function = transformPreviewMetadata;
        context = Text.encodeUtf8(originalUrl);
      };
    };

    let cycles = 230_000_000_000;
    ExperimentalCycles.add(cycles);

    try {
      let response = await ic.http_request(request);
      if (response.status < 200 or response.status >= 400) {
        Debug.print("Preview metadata fetch returned status " # Nat.toText(response.status) # " for " # requestUrl);
        return null;
      };

      let ?serialized = Text.decodeUtf8(response.body) else {
        Debug.print("Preview metadata transform returned a body that could not be decoded as UTF-8 for " # requestUrl);
        return null;
      };

      let ?metadata = deserializeMetadata(serialized) else {
        Debug.print("Preview metadata transform returned no useful metadata for " # requestUrl);
        return null;
      };

      ?metadata;
    } catch (error) {
      Debug.print("Failed to fetch preview metadata for " # requestUrl # ": " # Error.message(error));
      null;
    };
  };

  func previewSourceUrls(originalUrl : Text) : [Text] {
    let candidates = Buffer.Buffer<Text>(2);

    switch (rawGatewayUrl(originalUrl)) {
      case (?rawUrl) {
        if (rawUrl != originalUrl) {
          candidates.add(rawUrl);
        };
      };
      case null {};
    };

    candidates.add(originalUrl);
    Buffer.toArray(candidates);
  };

  func rawGatewayUrl(url : Text) : ?Text {
    let host = hostFromUrl(url);
    if (host == "") {
      return null;
    };

    if (Text.endsWith(host, #text(".raw.icp0.io")) or Text.endsWith(host, #text(".raw.ic0.app"))) {
      return ?url;
    };

    let replacementHost = if (Text.endsWith(host, #text(".icp0.io"))) {
      let suffix = ".icp0.io";
      let prefix = sliceText(host, 0, host.size() - suffix.size());
      if (prefix == "") {
        return null;
      };
      prefix # ".raw.icp0.io";
    } else if (Text.endsWith(host, #text(".ic0.app"))) {
      let suffix = ".ic0.app";
      let prefix = sliceText(host, 0, host.size() - suffix.size());
      if (prefix == "") {
        return null;
      };
      prefix # ".raw.ic0.app";
    } else {
      return null;
    };

    let origin = originFromUrl(url);
    let suffix = if (url.size() > origin.size()) {
      sliceText(url, origin.size(), url.size() - origin.size());
    } else {
      "";
    };

    ?(schemeFromUrl(url) # "://" # replacementHost # suffix);
  };

  func emptyMetadata() : UrlStore.UrlMetadata {
    {
      title = null;
      description = null;
      imageUrl = null;
      canonicalUrl = null;
      siteName = null;
    };
  };

  func serializeMetadata(metadata : UrlStore.UrlMetadata) : Text {
    Text.join(
      "\n",
      [
        serializeMetadataField("title", metadata.title),
        serializeMetadataField("description", metadata.description),
        serializeMetadataField("imageUrl", metadata.imageUrl),
        serializeMetadataField("canonicalUrl", metadata.canonicalUrl),
        serializeMetadataField("siteName", metadata.siteName),
      ].vals(),
    );
  };

  func serializeMetadataField(name : Text, value : ?Text) : Text {
    name # "=" # escapeSerializedValue(
      switch (value) {
        case (?text) text;
        case null "";
      }
    );
  };

  func deserializeMetadata(serialized : Text) : ?UrlStore.UrlMetadata {
    var title : ?Text = null;
    var description : ?Text = null;
    var imageUrl : ?Text = null;
    var canonicalUrl : ?Text = null;
    var siteName : ?Text = null;

    for (line in Text.split(serialized, #char('\n'))) {
      switch (findFrom(line, "=", 0)) {
        case (?separator) {
          let key = toLowerAscii(sliceText(line, 0, separator));
          let valueStart = separator + 1;
          let rawValue = if (valueStart < line.size()) {
            sliceText(line, valueStart, line.size() - valueStart);
          } else {
            "";
          };
          let value = normalizeSerializedField(rawValue);

          switch (key) {
            case ("title") title := value;
            case ("description") description := value;
            case ("imageurl") imageUrl := value;
            case ("canonicalurl") canonicalUrl := value;
            case ("sitename") siteName := value;
            case (_) {};
          };
        };
        case null {};
      };
    };

    let metadata : UrlStore.UrlMetadata = {
      title = title;
      description = description;
      imageUrl = imageUrl;
      canonicalUrl = canonicalUrl;
      siteName = siteName;
    };

    if (hasUsefulMetadata(?metadata)) {
      ?metadata;
    } else {
      null;
    };
  };

  func normalizeSerializedField(value : Text) : ?Text {
    cleanExtractedText(unescapeSerializedValue(value));
  };

  func escapeSerializedValue(value : Text) : Text {
    value
    |> Text.replace(_, #text("\\"), "\\\\")
    |> Text.replace(_, #text("\n"), "\\n")
    |> Text.replace(_, #text("\r"), "\\r");
  };

  func unescapeSerializedValue(value : Text) : Text {
    let chars = value.chars() |> Iter.toArray(_);
    var output = "";
    var index : Nat = 0;

    while (index < chars.size()) {
      if (chars[index] == '\\' and index + 1 < chars.size()) {
        let next = chars[index + 1];
        if (next == 'n') {
          output := output # "\n";
        } else if (next == 'r') {
          output := output # "\r";
        } else {
          output := output # Text.fromChar(next);
        };
        index += 2;
      } else {
        output := output # Text.fromChar(chars[index]);
        index += 1;
      };
    };

    output;
  };

  func extractMetadata(html : Text, originalUrl : Text) : UrlStore.UrlMetadata {
    let socialTitle = extractMetaContent(html, ["og:title", "twitter:title"]);
    let pageTitle = extractTitle(html);
    let socialDescription = extractMetaContent(html, ["og:description", "twitter:description", "description"]);
    let socialImage = extractMetaContent(html, ["og:image", "og:image:url", "twitter:image", "twitter:image:src"]);
    let ogUrl = extractMetaContent(html, ["og:url"]);
    let canonical = extractLinkHref(html, ["canonical"]);
    let imageSrc = extractLinkHref(html, ["image_src"]);
    let siteName = extractMetaContent(html, ["og:site_name"]);

    {
      title = firstSome([socialTitle, pageTitle]);
      description = socialDescription;
      imageUrl = normalizePossibleUrl(firstSome([socialImage, imageSrc]), originalUrl);
      canonicalUrl = normalizePossibleUrl(firstSome([ogUrl, canonical]), originalUrl);
      siteName = siteName;
    };
  };

  func firstSome(values : [?Text]) : ?Text {
    for (value in values.vals()) {
      switch (value) {
        case (?text) {
          if (text != "") {
            return ?text;
          };
        };
        case null {};
      };
    };
    null;
  };

  func hasUsefulMetadata(metadata : ?UrlStore.UrlMetadata) : Bool {
    switch (metadata) {
      case (?value) {
        firstSome([
          value.title,
          value.description,
          value.imageUrl,
          value.canonicalUrl,
          value.siteName,
        ]) != null;
      };
      case null false;
    };
  };

  func normalizePossibleUrl(value : ?Text, originalUrl : Text) : ?Text {
    switch (value) {
      case (?text) {
        let normalized = trimWhitespace(text);
        if (normalized == "") {
          null;
        } else if (Text.startsWith(normalized, #text("http://")) or Text.startsWith(normalized, #text("https://"))) {
          ?normalized;
        } else if (Text.startsWith(normalized, #text("//"))) {
          ?(schemeFromUrl(originalUrl) # ":" # normalized);
        } else if (Text.startsWith(normalized, #text("/"))) {
          ?(originFromUrl(originalUrl) # normalized);
        } else {
          resolveRelativeUrl(originalUrl, normalized);
        };
      };
      case null null;
    };
  };

  func resolveRelativeUrl(baseUrl : Text, relative : Text) : ?Text {
    let origin = originFromUrl(baseUrl);
    let basePath = pathFromUrl(baseUrl);
    let baseSegments = splitPathSegments(basePath);
    let resolved = Buffer.Buffer<Text>(baseSegments.size() + 4);
    let keepSegmentCount = if (Text.endsWith(basePath, #char('/')) or baseSegments.size() == 0) {
      baseSegments.size();
    } else {
      baseSegments.size() - 1;
    };

    var index = 0;
    while (index < keepSegmentCount) {
      resolved.add(baseSegments[index]);
      index += 1;
    };

    for (segment in Text.split(relative, #char('/'))) {
      if (segment == "" or segment == ".") {
        // Skip empty or current-directory path segments.
      } else if (segment == "..") {
        ignore resolved.removeLast();
      } else {
        resolved.add(segment);
      };
    };

    let joinedPath = joinPathSegments(Buffer.toArray(resolved));
    ?(origin # joinedPath);
  };

  func originFromUrl(url : Text) : Text {
    let parts = Text.split(url, #char('/'));
    var index = 0;
    var origin = "";

    for (part in parts) {
      if (index < 3) {
        if (index == 0) {
          origin := part;
        } else {
          origin := origin # "/" # part;
        };
      };
      index += 1;
    };

    origin;
  };

  func hostFromUrl(url : Text) : Text {
    let origin = originFromUrl(url);
    let prefix = schemeFromUrl(url) # "://";
    if (origin.size() <= prefix.size()) {
      "";
    } else {
      sliceText(origin, prefix.size(), origin.size() - prefix.size());
    };
  };

  func schemeFromUrl(url : Text) : Text {
    if (Text.startsWith(url, #text("http://"))) {
      "http";
    } else {
      "https";
    };
  };

  func pathFromUrl(url : Text) : Text {
    let origin = originFromUrl(url);
    if (url.size() <= origin.size()) {
      return "/";
    };

    let rawPath = sliceText(url, origin.size(), url.size() - origin.size());
    let stripped = stripQueryAndFragment(rawPath);
    if (stripped == "") {
      "/";
    } else if (Text.startsWith(stripped, #char('/'))) {
      stripped;
    } else {
      "/" # stripped;
    };
  };

  func splitPathSegments(path : Text) : [Text] {
    let segments = Buffer.Buffer<Text>(8);
    for (segment in Text.split(path, #char('/'))) {
      if (segment != "") {
        segments.add(segment);
      };
    };
    Buffer.toArray(segments);
  };

  func joinPathSegments(segments : [Text]) : Text {
    if (segments.size() == 0) {
      return "/";
    };

    let buffer = Buffer.Buffer<Text>(segments.size());
    for (segment in segments.vals()) {
      buffer.add(segment);
    };
    "/" # Text.join("/", Buffer.toArray(buffer).vals());
  };

  func stripQueryAndFragment(value : Text) : Text {
    let queryIndex = findFrom(value, "?", 0);
    let fragmentIndex = findFrom(value, "#", 0);

    let end = switch (queryIndex, fragmentIndex) {
      case (?queryPos, ?fragment) {
        if (queryPos < fragment) {
          queryPos;
        } else {
          fragment;
        };
      };
      case (?queryPos, null) queryPos;
      case (null, ?fragment) fragment;
      case (null, null) value.size();
    };

    sliceText(value, 0, end);
  };

  func extractMetaContent(html : Text, candidates : [Text]) : ?Text {
    for (tag in collectTags(html, "meta").vals()) {
      let attributes = parseTagAttributes(tag);
      let tagName = firstSome([
        getParsedAttribute(attributes, "property"),
        getParsedAttribute(attributes, "name"),
      ]);

      switch (tagName) {
        case (?value) {
          if (matchesCandidate(candidates, value)) {
            let content = firstSome([
              getParsedAttribute(attributes, "content"),
              getParsedAttribute(attributes, "value"),
            ]);
            if (content != null) {
              return content;
            };
          };
        };
        case null {};
      };
    };
    null;
  };

  func extractLinkHref(html : Text, relCandidates : [Text]) : ?Text {
    for (tag in collectTags(html, "link").vals()) {
      let attributes = parseTagAttributes(tag);
      switch (getParsedAttribute(attributes, "rel")) {
        case (?rel) {
          if (relContainsCandidate(rel, relCandidates)) {
            let href = getParsedAttribute(attributes, "href");
            if (href != null) {
              return href;
            };
          };
        };
        case null {};
      };
    };
    null;
  };

  func extractTitle(html : Text) : ?Text {
    let lowerHtml = toLowerAscii(html);
    let ?start = findFrom(lowerHtml, "<title>", 0) else return null;
    let contentStart = start + 7;
    let ?end = findFrom(lowerHtml, "</title>", contentStart) else return null;
    let raw = sliceText(html, contentStart, end - contentStart);
    cleanExtractedText(raw);
  };

  func collectTags(html : Text, tagName : Text) : [Text] {
    let lowerHtml = toLowerAscii(html);
    let marker = "<" # tagName;
    let tags = Buffer.Buffer<Text>(8);
    var searchStart = 0;

    loop {
      let maybeIndex = findFrom(lowerHtml, marker, searchStart);
      switch (maybeIndex) {
        case null { return Buffer.toArray(tags) };
        case (?index) {
          let endIndex = switch (findFrom(lowerHtml, ">", index)) {
            case (?value) value;
            case null lowerHtml.size();
          };
          tags.add(sliceText(html, index, endIndex - index + 1));
          searchStart := endIndex + 1;
        };
      };
    };
  };

  func parseTagAttributes(tag : Text) : [(Text, Text)] {
    let chars = tag.chars() |> Iter.toArray(_);
    let attributes = Buffer.Buffer<(Text, Text)>(8);
    var index : Nat = 0;

    while (index < chars.size() and chars[index] != ' ' and chars[index] != '>') {
      index += 1;
    };

    while (index < chars.size()) {
      while (index < chars.size() and (isWhitespace(chars[index]) or chars[index] == '<' or chars[index] == '/')) {
        index += 1;
      };

      if (index >= chars.size() or chars[index] == '>') {
        return Buffer.toArray(attributes);
      };

      let nameStart = index;
      while (
        index < chars.size() and
        not isWhitespace(chars[index]) and
        chars[index] != '=' and
        chars[index] != '>' and
        chars[index] != '/'
      ) {
        index += 1;
      };

      let attributeName = toLowerAscii(sliceChars(chars, nameStart, index - nameStart));

      while (index < chars.size() and isWhitespace(chars[index])) {
        index += 1;
      };

      var attributeValue = "";
      if (index < chars.size() and chars[index] == '=') {
        index += 1;
        while (index < chars.size() and isWhitespace(chars[index])) {
          index += 1;
        };

        if (index < chars.size() and isAttributeQuote(chars[index])) {
          let quote = chars[index];
          index += 1;
          let valueStart = index;
          while (index < chars.size() and chars[index] != quote) {
            index += 1;
          };
          attributeValue := sliceChars(chars, valueStart, index - valueStart);
          if (index < chars.size()) {
            index += 1;
          };
        } else {
          let valueStart = index;
          while (index < chars.size() and not isWhitespace(chars[index]) and chars[index] != '>' and chars[index] != '/') {
            index += 1;
          };
          attributeValue := sliceChars(chars, valueStart, index - valueStart);
        };
      };

      if (attributeName != "") {
        attributes.add((attributeName, switch (cleanExtractedText(attributeValue)) { case (?value) value; case null "" }));
      };
    };

    Buffer.toArray(attributes);
  };

  func getParsedAttribute(attributes : [(Text, Text)], attributeName : Text) : ?Text {
    for ((name, value) in attributes.vals()) {
      if (name == toLowerAscii(attributeName) and value != "") {
        return ?value;
      };
    };
    null;
  };

  func matchesCandidate(candidates : [Text], value : Text) : Bool {
    let normalized = toLowerAscii(value);
    for (candidate in candidates.vals()) {
      if (normalized == toLowerAscii(candidate)) {
        return true;
      };
    };
    false;
  };

  func relContainsCandidate(relValue : Text, candidates : [Text]) : Bool {
    for (token in Text.split(toLowerAscii(relValue), #char(' '))) {
      if (token != "" and matchesCandidate(candidates, token)) {
        return true;
      };
    };
    false;
  };

  func sliceChars(chars : [Char], start : Nat, length : Nat) : Text {
    var output = "";
    var index = start;
    while (index < start + length and index < chars.size()) {
      output := output # Text.fromChar(chars[index]);
      index += 1;
    };
    output;
  };

  func cleanExtractedText(value : Text) : ?Text {
    let trimmed = trimWhitespace(value);
    if (trimmed == "") {
      null;
    } else {
      ?decodeHtmlEntities(trimmed);
    };
  };

  func trimWhitespace(value : Text) : Text {
    let chars = value.chars() |> Iter.toArray(_);
    if (chars.size() == 0) {
      return value;
    };

    var start : Nat = 0;
    var finished = false;
    while (start < chars.size() and not finished) {
      if (isWhitespace(chars[start])) {
        start += 1;
      } else {
        finished := true;
      };
    };

    if (start == chars.size()) {
      return "";
    };

    var end = chars.size();
    finished := false;
    while (end > start and not finished) {
      if (isWhitespace(chars[end - 1])) {
        end -= 1;
      } else {
        finished := true;
      };
    };

    var result = "";
    var index = start;
    while (index < end) {
      result := result # Text.fromChar(chars[index]);
      index += 1;
    };
    result;
  };

  func isWhitespace(char : Char) : Bool {
    char == ' ' or char == '\n' or char == '\r' or char == '\t';
  };

  func isAttributeQuote(char : Char) : Bool {
    let code = Char.toNat32(char);
    code == 34 or code == 39;
  };

  func toLowerAscii(value : Text) : Text {
    var result = "";
    for (char in value.chars()) {
      let code = Char.toNat32(char);
      if (code >= 65 and code <= 90) {
        result := result # Text.fromChar(Char.fromNat32(code + 32));
      } else {
        result := result # Text.fromChar(char);
      };
    };
    result;
  };

  func decodeHtmlEntities(value : Text) : Text {
    value
    |> Text.replace(_, #text("&amp;"), "&")
    |> Text.replace(_, #text("&quot;"), "\"")
    |> Text.replace(_, #text("&#39;"), "'")
    |> Text.replace(_, #text("&apos;"), "'")
    |> Text.replace(_, #text("&lt;"), "<")
    |> Text.replace(_, #text("&gt;"), ">");
  };

  func sliceText(value : Text, start : Nat, length : Nat) : Text {
    let chars = value.chars();
    var index : Nat = 0;
    var output = "";
    for (char in chars) {
      if (index >= start and index < start + length) {
        output := output # Text.fromChar(char);
      };
      index += 1;
    };
    output;
  };

  func findFrom(haystack : Text, needle : Text, start : Nat) : ?Nat {
    if (needle == "") {
      return ?start;
    };

    let haystackChars = haystack.chars() |> Iter.toArray(_);
    let needleChars = needle.chars() |> Iter.toArray(_);
    let haystackSize = haystackChars.size();
    let needleSize = needleChars.size();
    if (needleSize > haystackSize or start >= haystackSize) {
      return null;
    };

    let lastStart = haystackSize - needleSize;
    var index = start;
    while (index <= lastStart) {
      var matched = true;
      var offset = 0;
      while (offset < needleChars.size()) {
        if (haystackChars[index + offset] != needleChars[offset]) {
          matched := false;
          offset := needleChars.size();
        } else {
          offset += 1;
        };
      };
      if (matched) {
        return ?index;
      };
      index += 1;
    };
    null;
  };

  func buildShortLinkHeadUpgradeResponse() : Liminal.RawQueryHttpResponse {
    {
      status_code = 200;
      headers = [];
      body = Blob.fromArray([]);
      streaming_strategy = null;
      upgrade = ?true;
    };
  };

  func buildShortLinkHeadResponse(statusCode : Nat16) : Liminal.RawUpdateHttpResponse {
    {
      status_code = statusCode;
      headers = [
        ("Content-Type", "text/html; charset=utf-8"),
        ("Cache-Control", "no-store, max-age=0"),
        ("X-Robots-Tag", "noindex, noarchive"),
      ];
      body = Blob.fromArray([]);
      streaming_strategy = null;
    };
  };

  func requestPath(url : Text) : Text {
    if (Text.startsWith(url, #text("http://")) or Text.startsWith(url, #text("https://"))) {
      pathFromUrl(url);
    } else {
      let stripped = stripQueryAndFragment(url);
      if (Text.startsWith(stripped, #char('/'))) {
        stripped;
      } else {
        "/" # stripped;
      };
    };
  };

  func shortCodeFromRequestUrl(url : Text) : ?Text {
    let path = requestPath(url);
    let prefix = "/s/";
    if (not Text.startsWith(path, #text(prefix))) {
      return null;
    };

    let shortCode = sliceText(path, prefix.size(), path.size() - prefix.size());
    if (shortCode == "" or findFrom(shortCode, "/", 0) != null) {
      return null;
    };

    ?shortCode;
  };

  transient var routerConfig : RouterMiddleware.Config = buildRouterConfig();

  transient var app : Liminal.App = buildApp(routerConfig);

  public query func http_request(request : Liminal.RawQueryHttpRequest) : async Liminal.RawQueryHttpResponse {
    if (toLowerAscii(request.method) == "head" and shortCodeFromRequestUrl(request.url) != null) {
      return buildShortLinkHeadUpgradeResponse();
    };

    app.http_request(request);
  };

  public func http_request_update(request : Liminal.RawUpdateHttpRequest) : async Liminal.RawUpdateHttpResponse {
    if (toLowerAscii(request.method) == "head") {
      switch (shortCodeFromRequestUrl(request.url)) {
        case (?shortCode) {
          if (urlStore.getUrlByShortCode(shortCode) != null) {
            return buildShortLinkHeadResponse(200);
          };
          return buildShortLinkHeadResponse(404);
        };
        case null {};
      };
    };

    await* app.http_request_update(request);
  };
};
