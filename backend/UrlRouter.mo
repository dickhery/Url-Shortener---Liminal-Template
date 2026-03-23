import Array "mo:core@1/Array";
import Route "mo:liminal/Route";
import Nat "mo:core@1/Nat";
import Debug "mo:core@1/Debug";
import UrlStore "UrlStore";
import Serializer "Serializer";
import Serde "mo:serde";
import RouteContext "mo:liminal/RouteContext";
import Text "mo:core@1/Text";
import Iter "mo:core@1/Iter";
import UrlKit "mo:url-kit@3";
import Runtime "mo:core@1/Runtime";
import Principal "mo:core@1/Principal";
import Pricing "Pricing";

module {

  public class Router(
    store : UrlStore.Store,
    defaultHost : Text,
  ) = self {

    func buildRedirectHeaders() : [(Text, Text)] {
      [
        ("Content-Type", "text/html; charset=utf-8"),
        ("Cache-Control", "no-store, max-age=0"),
        ("X-Robots-Tag", "noindex, noarchive"),
      ];
    };

    public func getAllUrls(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let urls = Array.map<UrlStore.Url, UrlStore.UrlView>(store.getAllUrls(), store.toView);
      routeContext.buildResponse(#ok, #content(toCandid(to_candid (urls))));
    };

    public func redirect<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let shortCode = routeContext.getRouteParam("shortCode");

      switch (store.recordVisit(shortCode)) {
        case (#notFound) {
          routeContext.buildResponse(#notFound, #error(#message("Short URL not found")));
        };
        case (#inactive(url)) {
          let shortUrl = buildShortUrl(routeContext, shortCode);
          let html = generateInactiveHtml(shortUrl, shortCode, store.toView(url));
          routeContext.buildResponse(
            #forbidden,
            #custom({
              body = Text.encodeUtf8(html);
              headers = buildRedirectHeaders();
            }),
          );
        };
        case (#ok(url)) {
          let shortUrl = buildShortUrl(routeContext, shortCode);
          let html = generateRedirectHtml(shortUrl, shortCode, url.originalUrl, url.metadata);
          routeContext.buildResponse(
            #ok,
            #custom({
              body = Text.encodeUtf8(html);
              headers = buildRedirectHeaders();
            }),
          );
        };
      };
    };

    public func getStats(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let shortCode = routeContext.getRouteParam("shortCode");

      switch (store.getUrlByShortCode(shortCode)) {
        case (null) {
          routeContext.buildResponse(#notFound, #error(#message("Short URL not found")));
        };
        case (?url) {
          routeContext.buildResponse(#ok, #content(toCandid(to_candid (store.toView(url)))));
        };
      };
    };

    public func createShortUrl<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      Debug.print("Creating short URL...");
      let contentType = routeContext.httpContext.getHeader("content-type");

      let createRequest : UrlStore.CreateRequest = switch (contentType) {
        case (?"application/x-www-form-urlencoded") {
          parseFormData(routeContext);
        };
        case (?"text/plain") {
          let ?body : ?Text = routeContext.parseUtf8Body() else Runtime.trap("Failed to decode request body as UTF-8");
          {
            originalUrl = body;
            customSlug = null;
            purchasedClicks = Pricing.minimumPurchaseClicks;
          };
        };
        case _ {
          switch (routeContext.parseJsonBody<UrlStore.CreateRequest>(Serializer.deserializeCreateRequest)) {
            case (#err(e)) return routeContext.buildResponse(#badRequest, #error(#message("Failed to parse request. Error: " # e)));
            case (#ok(req)) req;
          };
        };
      };

      switch (store.create(createRequest, Principal.fromText("2vxsx-fae"), null)) {
        case (#err(errorMessage)) {
          routeContext.buildResponse(#badRequest, #error(#message(errorMessage)));
        };
        case (#ok(url)) {
          routeContext.buildResponse(#created, #content(toCandid(to_candid (store.toView(url)))));
        };
      };
    };

    public func deleteUrl<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let idText = routeContext.getRouteParam("id");
      let ?id = Nat.fromText(idText) else return routeContext.buildResponse(#badRequest, #error(#message("Invalid id '" # idText # "', must be a positive integer")));

      switch (store.delete(id, Principal.fromText("2vxsx-fae"))) {
        case (#ok()) routeContext.buildResponse(#noContent, #empty);
        case (#err(message)) {
          if (message == "URL not found") {
            routeContext.buildResponse(#notFound, #error(#message(message)));
          } else {
            routeContext.buildResponse(#forbidden, #error(#message(message)));
          };
        };
      };
    };

    private func parseFormData(routeContext : RouteContext.RouteContext) : UrlStore.CreateRequest {
      let ?body : ?Text = routeContext.parseUtf8Body() else Runtime.trap("Failed to decode request body as UTF-8");
      var originalUrl = "";
      var customSlug : ?Text = null;
      var purchasedClicks = Pricing.minimumPurchaseClicks;

      let pairs = Text.split(body, #char('&'));
      for (pair in pairs) {
        let keyValue = Text.split(pair, #char('='));
        let keyValueArray = Iter.toArray(keyValue);
        if (keyValueArray.size() == 2) {
          let key = switch (UrlKit.decodeText(keyValueArray[0])) {
            case (#ok(decoded)) decoded;
            case (#err(e)) Runtime.trap("Failed to decode key: " # e);
          };
          let value = switch (UrlKit.decodeText(keyValueArray[1])) {
            case (#ok(decoded)) decoded;
            case (#err(e)) Runtime.trap("Failed to decode value: " # e);
          };

          if (key == "url") {
            originalUrl := value;
          } else if (key == "slug") {
            customSlug := ?value;
          } else if (key == "clicks") {
            let ?parsedClicks = Nat.fromText(value) else Runtime.trap("Failed to decode clicks as Nat");
            purchasedClicks := parsedClicks;
          };
        };
      };

      {
        originalUrl = originalUrl;
        customSlug = customSlug;
        purchasedClicks = purchasedClicks;
      };
    };

    func toCandid(value : Blob) : Serde.Candid.Candid {
      let urlKeys = ["id", "originalUrl", "shortCode", "clicks", "createdAt", "metadata", "allowance"];
      let options : ?Serde.Options = ?{
        renameKeys = [];
        blob_contains_only_values = false;
        types = null;
        use_icrc_3_value_type = false;
      };
      switch (Serde.Candid.decode(value, urlKeys, options)) {
        case (#err(e)) {
          Debug.print("Failed to decode URL Candid. Error: " # e);
          Runtime.trap("Failed to decode URL Candid. Error: " # e);
        };
        case (#ok(candid)) {
          if (candid.size() != 1) {
            Debug.print("Invalid Candid response. Expected 1 element, got " # Nat.toText(candid.size()));
            Runtime.trap("Invalid Candid response. Expected 1 element, got " # Nat.toText(candid.size()));
          };
          candid[0];
        };
      };
    };

    func generateRedirectHtml(shortUrl : Text, shortCode : Text, originalUrl : Text, metadata : ?UrlStore.UrlMetadata) : Text {
      let escapedOriginalUrl = escapeHtml(originalUrl);
      let escapedShortUrl = escapeHtml(shortUrl);
      let title = switch (metadata) {
        case (?data) chooseText(data.title, "TinyICP Short Link - " # shortCode);
        case null "TinyICP Short Link - " # shortCode;
      };
      let description = switch (metadata) {
        case (?data) chooseText(data.description, "Shared via TinyICP.");
        case null "Shared via TinyICP.";
      };
      let siteName = switch (metadata) {
        case (?data) chooseText(data.siteName, "TinyICP");
        case null "TinyICP";
      };
      let escapedTitle = escapeHtml(title);
      let escapedDescription = escapeHtml(description);
      let escapedSiteName = escapeHtml(siteName);
      let imageUrl = switch (metadata) {
        case (?data) {
          switch (data.imageUrl) {
            case (?value) {
              if (value != "") {
                ?value;
              } else {
                null;
              };
            };
            case null null;
          };
        };
        case null null;
      };
      let hasImage = imageUrl != null;
      let twitterCard = if (hasImage) "summary_large_image" else "summary";
      let imageMeta = switch (imageUrl) {
        case (?value) {
          let escapedImageUrl = escapeHtml(value);
          "    <meta property=\"og:image\" content=\"" # escapedImageUrl # "\">\n" #
          "    <meta property=\"og:image:url\" content=\"" # escapedImageUrl # "\">\n" #
          "    <meta property=\"og:image:secure_url\" content=\"" # escapedImageUrl # "\">\n" #
          "    <meta name=\"twitter:image\" content=\"" # escapedImageUrl # "\">\n";
        };
        case null "";
      };
      let noscriptRefresh = "    <noscript><meta http-equiv=\"refresh\" content=\"0; url=" # escapedOriginalUrl # "\"></noscript>\n";

      "<!DOCTYPE html>\n" #
      "<html lang=\"en\">\n" #
      "<head>\n" #
      "    <meta charset=\"UTF-8\">\n" #
      "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n" #
      "    <title>" # escapedTitle # "</title>\n" #
      "    <link rel=\"canonical\" href=\"" # escapedShortUrl # "\">\n" #
      "    <meta property=\"og:type\" content=\"website\">\n" #
      "    <meta property=\"og:url\" content=\"" # escapedShortUrl # "\">\n" #
      "    <meta property=\"og:title\" content=\"" # escapedTitle # "\">\n" #
      "    <meta property=\"og:description\" content=\"" # escapedDescription # "\">\n" #
      "    <meta property=\"og:site_name\" content=\"" # escapedSiteName # "\">\n" #
      imageMeta #
      "    <meta name=\"twitter:card\" content=\"" # twitterCard # "\">\n" #
      "    <meta name=\"twitter:url\" content=\"" # escapedShortUrl # "\">\n" #
      "    <meta name=\"twitter:title\" content=\"" # escapedTitle # "\">\n" #
      "    <meta name=\"twitter:description\" content=\"" # escapedDescription # "\">\n" #
      noscriptRefresh #
      "    <style>\n" #
      "      body { font-family: monospace; background: #000; color: #00ff9c; padding: 40px; text-align: center; font-size: 18px; }\n" #
      "      .panel { max-width: 640px; margin: 10vh auto; border: 1px solid #00ff9c; padding: 32px; box-shadow: 0 0 24px rgba(0, 255, 156, 0.15); background: rgba(0,0,0,0.92); }\n" #
      "      a { color: #8fffd2; }\n" #
      "      .muted { opacity: 0.75; font-size: 14px; word-break: break-all; }\n" #
      "    </style>\n" #
      "</head>\n" #
      "<body>\n" #
      "    <div class=\"panel\">\n" #
      "      <h1>🌐 TinyICP</h1>\n" #
      "      <p>Redirecting you to the original URL...</p>\n" #
      "      <p class=\"muted\">" # escapedOriginalUrl # "</p>\n" #
      "      <p>If you are not redirected automatically, <a href=\"" # escapedOriginalUrl # "\">click here</a>.</p>\n" #
      "    </div>\n" #
      "    <script>setTimeout(() => { window.location.replace('" # escapeJsString(originalUrl) # "'); }, 300);</script>\n" #
      "</body>\n" #
      "</html>";
    };

    func generateInactiveHtml(shortUrl : Text, shortCode : Text, urlView : UrlStore.UrlView) : Text {
      let escapedShortUrl = escapeHtml(shortUrl);
      let title = "TinyICP Link Paused - " # shortCode;
      let description =
        "This short URL is currently inactive because its prepaid click allowance has been exhausted. The owner can top it up in TinyICP to reactivate it.";
      let siteName = switch (urlView.metadata) {
        case (?data) chooseText(data.siteName, "TinyICP");
        case null "TinyICP";
      };
      let escapedTitle = escapeHtml(title);
      let escapedDescription = escapeHtml(description);
      let escapedSiteName = escapeHtml(siteName);

      "<!DOCTYPE html>\n" #
      "<html lang=\"en\">\n" #
      "<head>\n" #
      "    <meta charset=\"UTF-8\">\n" #
      "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n" #
      "    <title>" # escapedTitle # "</title>\n" #
      "    <link rel=\"canonical\" href=\"" # escapedShortUrl # "\">\n" #
      "    <meta property=\"og:type\" content=\"website\">\n" #
      "    <meta property=\"og:url\" content=\"" # escapedShortUrl # "\">\n" #
      "    <meta property=\"og:title\" content=\"" # escapedTitle # "\">\n" #
      "    <meta property=\"og:description\" content=\"" # escapedDescription # "\">\n" #
      "    <meta property=\"og:site_name\" content=\"" # escapedSiteName # "\">\n" #
      "    <meta name=\"twitter:card\" content=\"summary\">\n" #
      "    <meta name=\"twitter:url\" content=\"" # escapedShortUrl # "\">\n" #
      "    <meta name=\"twitter:title\" content=\"" # escapedTitle # "\">\n" #
      "    <meta name=\"twitter:description\" content=\"" # escapedDescription # "\">\n" #
      "    <style>\n" #
      "      body { font-family: monospace; background: #000; color: #00ff9c; padding: 40px; text-align: center; font-size: 18px; }\n" #
      "      .panel { max-width: 700px; margin: 10vh auto; border: 1px solid #ffcc00; padding: 32px; box-shadow: 0 0 24px rgba(255, 204, 0, 0.15); background: rgba(0,0,0,0.92); }\n" #
      "      .badge { display: inline-block; border: 1px solid #ffcc00; color: #ffcc00; padding: 6px 12px; margin-bottom: 16px; text-transform: uppercase; letter-spacing: 0.08em; font-size: 14px; }\n" #
      "      .muted { opacity: 0.75; font-size: 14px; }\n" #
      "      .stats { margin-top: 18px; color: #d7fff0; }\n" #
      "    </style>\n" #
      "</head>\n" #
      "<body>\n" #
      "    <div class=\"panel\">\n" #
      "      <div class=\"badge\">Paused</div>\n" #
      "      <h1>TinyICP URL paused</h1>\n" #
      "      <p>This short URL has used all of its prepaid clicks and is inactive until the owner tops it up.</p>\n" #
      "      <p class=\"muted\">The owner can reactivate it at any time by purchasing more clicks in the TinyICP app.</p>\n" #
      "      <div class=\"stats\">\n" #
      "        <p><strong>Short URL:</strong> " # escapedShortUrl # "</p>\n" #
      "        <p><strong>Total clicks served:</strong> " # Nat.toText(urlView.clicks) # "</p>\n" #
      "        <p><strong>Remaining prepaid clicks:</strong> " # Nat.toText(urlView.allowance.remainingClicks) # "</p>\n" #
      "      </div>\n" #
      "    </div>\n" #
      "</body>\n" #
      "</html>";
    };

    func chooseText(candidate : ?Text, fallback : Text) : Text {
      switch (candidate) {
        case (?value) {
          if (value != "") {
            value;
          } else {
            fallback;
          };
        };
        case null fallback;
      };
    };

    func escapeHtml(value : Text) : Text {
      value
      |> Text.replace(_, #text("&"), "&amp;")
      |> Text.replace(_, #text("\""), "&quot;")
      |> Text.replace(_, #text("'"), "&#39;")
      |> Text.replace(_, #text("<"), "&lt;")
      |> Text.replace(_, #text(">"), "&gt;");
    };

    func escapeJsString(value : Text) : Text {
      value
      |> Text.replace(_, #text("\\"), "\\\\")
      |> Text.replace(_, #text("'"), "\\'")
      |> Text.replace(_, #text("\n"), "\\n")
      |> Text.replace(_, #text("\r"), "\\r");
    };

    func buildShortUrl(routeContext : RouteContext.RouteContext, shortCode : Text) : Text {
      let host = switch (routeContext.getHeader("host")) {
        case (?value) {
          if (value != "") {
            value;
          } else {
            defaultHost;
          };
        };
        case null defaultHost;
      };
      let scheme = if (hostUsesHttp(host)) "http" else "https";
      scheme # "://" # host # "/s/" # shortCode;
    };

    func hostUsesHttp(host : Text) : Bool {
      Text.contains(host, #text("localhost")) or
      Text.startsWith(host, #text("127.0.0.1")) or
      Text.startsWith(host, #text("0.0.0.0"));
    };
  };
};
