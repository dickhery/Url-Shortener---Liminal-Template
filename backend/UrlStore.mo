import Array "mo:core@1/Array";
import Map "mo:core@1/Map";
import Iter "mo:core@1/Iter";
import Nat "mo:core@1/Nat";
import Result "mo:core@1/Result";
import Text "mo:core@1/Text";
import Time "mo:core@1/Time";
import Principal "mo:core@1/Principal";
import Char "mo:core@1/Char";
import BTree "mo:stableheapbtreemap/BTree";
import Debug "mo:core@1/Debug";
import Pricing "Pricing";
import Buffer "mo:base/Buffer";

module {
  public let allowanceExhaustedMessage : Text =
    "This TinyICP URL is paused because its prepaid click allowance has run out. Top it up in the TinyICP app to reactivate it.";

  public type StableData = {
    urls : BTree.BTree<Nat, Url>;
    nextId : Nat;
  };

  public type BillingStableData = {
    allowances : BTree.BTree<Nat, UrlAllowance>;
  };

  public type ReservationStableData = {
    reservations : BTree.BTree<Text, ShortCodeReservation>;
  };

  public type UrlMetadata = {
    title : ?Text;
    description : ?Text;
    imageUrl : ?Text;
    canonicalUrl : ?Text;
    siteName : ?Text;
  };

  public type Url = {
    id : Nat;
    originalUrl : Text;
    shortCode : Text;
    clicks : Nat;
    createdAt : Int;
    owner : Principal;
    metadata : ?UrlMetadata;
  };

  public type UrlAllowance = {
    totalPurchasedClicks : Nat;
    remainingClicks : Nat;
    lastTopUpAt : Int;
  };

  public type ShortCodeReservation = {
    shortCode : Text;
    expiresAt : Int;
    isCustom : Bool;
  };

  public type UrlAllowanceView = {
    totalPurchasedClicks : Nat;
    remainingClicks : Nat;
    isActive : Bool;
  };

  public type UrlView = {
    id : Nat;
    originalUrl : Text;
    shortCode : Text;
    clicks : Nat;
    createdAt : Int;
    metadata : ?UrlMetadata;
    allowance : UrlAllowanceView;
  };

  public type CreateRequest = {
    originalUrl : Text;
    customSlug : ?Text;
    purchasedClicks : Nat;
  };

  public type VisitResult = {
    #ok : Url;
    #inactive : Url;
    #notFound;
  };

  public class Store(
    stableData : StableData,
    billingStableData : BillingStableData,
    reservationStableData : ReservationStableData,
  ) = self {

    var nextId = stableData.nextId;

    let slugToIdMap : Map.Map<Text, Nat> = stableData.urls
    |> BTree.entries(_)
    |> Iter.map<(Nat, Url), (Text, Nat)>(
      _,
      func((_, url) : (Nat, Url)) : (Text, Nat) = (url.shortCode, url.id),
    )
    |> Map.fromIter<Text, Nat>(_, Text.compare);

    let reservedSlugToOwnerMap : Map.Map<Text, Text> = reservationStableData.reservations
    |> BTree.entries(_)
    |> Iter.map<(Text, ShortCodeReservation), (Text, Text)>(
      _,
      func((ownerText, reservation) : (Text, ShortCodeReservation)) : (Text, Text) = (
        reservation.shortCode,
        ownerText,
      ),
    )
    |> Map.fromIter<Text, Text>(_, Text.compare);

    public func getAllUrls() : [Url] {
      BTree.entries(stableData.urls)
      |> Iter.map(
        _,
        func((_, url) : (Nat, Url)) : Url = url,
      )
      |> Iter.toArray(_);
    };

    public func getUrlsByOwner(owner : Principal) : [UrlView] {
      BTree.entries(stableData.urls)
      |> Iter.map(
        _,
        func((_, url) : (Nat, Url)) : ?UrlView {
          if (Principal.equal(url.owner, owner)) {
            ?toView(url);
          } else {
            null;
          };
        },
      )
      |> Iter.filterMap(_, func(url : ?UrlView) : ?UrlView = url)
      |> Iter.toArray(_);
    };

    public func getUrlByShortCode(shortCode : Text) : ?Url {
      let ?id = Map.get(slugToIdMap, Text.compare, shortCode) else return null;
      BTree.get(stableData.urls, Nat.compare, id);
    };

    public func getUrlById(id : Nat) : ?Url {
      BTree.get(stableData.urls, Nat.compare, id);
    };

    public func recordVisit(shortCode : Text) : VisitResult {
      let ?url = getUrlByShortCode(shortCode) else return #notFound;
      let allowance = ensurePersistedAllowance(url.id);
      let remainingClicks = remainingClicksFor(url, allowance);

      if (remainingClicks == 0) {
        return #inactive(url);
      };

      Debug.print(
        "Recording click for shortCode: " # shortCode #
        " (ID: " # Nat.toText(url.id) # "), current clicks: " # Nat.toText(url.clicks) #
        ", remaining prepaid clicks: " # Nat.toText(remainingClicks)
      );

      let updatedUrl : Url = {
        url with
        clicks = url.clicks + 1;
      };

      ignore BTree.insert(stableData.urls, Nat.compare, url.id, updatedUrl);
      #ok(updatedUrl);
    };

    public func validateClickPurchase(purchasedClicks : Nat) : Result.Result<(), Text> {
      if (purchasedClicks < Pricing.minimumPurchaseClicks) {
        return #err(
          "TinyICP requires at least " # Nat.toText(Pricing.minimumPurchaseClicks) #
          " prepaid clicks per purchase."
        );
      };

      if (purchasedClicks % Pricing.clickBundleSize != 0) {
        return #err(
          "TinyICP click purchases must be made in " # Nat.toText(Pricing.clickBundleSize) #
          "-click increments."
        );
      };

      #ok(());
    };

    public func validateCreateRequest(request : CreateRequest) : Result.Result<(), Text> {
      validateCreateRequestForOwner(request, null);
    };

    public func validateCreateRequestForCaller(
      request : CreateRequest,
      owner : Principal,
    ) : Result.Result<(), Text> {
      validateCreateRequestForOwner(request, ?Principal.toText(owner));
    };

    public func checkShortCodeAvailability(
      shortCode : Text,
      owner : ?Principal,
    ) : Result.Result<Bool, Text> {
      pruneExpiredReservations();

      if (not isValidSlug(shortCode)) {
        return #err(
          "Invalid custom slug. Use only letters, numbers, hyphens, and underscores"
        );
      };

      #ok(isShortCodeAvailable(shortCode, principalText(owner)));
    };

    public func reserveShortCode(
      owner : Principal,
      requestedShortCode : ?Text,
      reservationDurationNanos : Int,
    ) : Result.Result<Text, Text> {
      switch (requestedShortCode) {
        case (?shortCode) {
          if (not isValidSlug(shortCode)) {
            return #err(
              "Invalid custom slug. Use only letters, numbers, hyphens, and underscores"
            );
          };

          pruneExpiredReservations();

          let ownerText = Principal.toText(owner);
          if (not isShortCodeAvailable(shortCode, ?ownerText)) {
            return #err("Custom slug already exists");
          };

          let expiresAt = Time.now() + reservationDurationNanos;

          switch (BTree.get(reservationStableData.reservations, Text.compare, ownerText)) {
            case (?reservation) {
              if (reservation.shortCode != shortCode or not reservation.isCustom) {
                releaseReservationByOwnerText(ownerText);
              };
            };
            case null {};
          };

          let reservation = {
            shortCode = shortCode;
            expiresAt = expiresAt;
            isCustom = true;
          };
          ignore BTree.insert(
            reservationStableData.reservations,
            Text.compare,
            ownerText,
            reservation,
          );
          Map.add(reservedSlugToOwnerMap, Text.compare, shortCode, ownerText);
          #ok(shortCode);
        };
        case null {
          #ok(reserveGeneratedShortCode(owner, reservationDurationNanos));
        };
      };
    };

    public func reserveGeneratedShortCode(owner : Principal, reservationDurationNanos : Int) : Text {
      pruneExpiredReservations();

      let ownerText = Principal.toText(owner);
      let expiresAt = Time.now() + reservationDurationNanos;

      switch (BTree.get(reservationStableData.reservations, Text.compare, ownerText)) {
        case (?reservation) {
          if (reservation.isCustom) {
            releaseReservationByOwnerText(ownerText);
          } else {
            let renewedReservation = {
              shortCode = reservation.shortCode;
              expiresAt = expiresAt;
              isCustom = false;
            };
            ignore BTree.insert(
              reservationStableData.reservations,
              Text.compare,
              ownerText,
              renewedReservation,
            );
            return renewedReservation.shortCode;
          };
        };
        case null {
        };
      };

      let shortCode = generateShortCode();
      let reservation = {
        shortCode = shortCode;
        expiresAt = expiresAt;
        isCustom = false;
      };
      ignore BTree.insert(
        reservationStableData.reservations,
        Text.compare,
        ownerText,
        reservation,
      );
      Map.add(reservedSlugToOwnerMap, Text.compare, shortCode, ownerText);
      shortCode;
    };

    public func releaseGeneratedShortCode(owner : Principal) {
      releaseReservationByOwnerText(Principal.toText(owner));
    };

    private func validateCreateRequestForOwner(
      request : CreateRequest,
      ownerText : ?Text,
    ) : Result.Result<(), Text> {
      if (not isValidUrl(request.originalUrl)) {
        return #err("Invalid URL format: " # request.originalUrl);
      };

      switch (validateClickPurchase(request.purchasedClicks)) {
        case (#err(message)) return #err(message);
        case (#ok(())) {};
      };

      switch (request.customSlug) {
        case (?slug) {
          if (not isValidSlug(slug)) {
            return #err("Invalid custom slug. Use only letters, numbers, hyphens, and underscores");
          };
          if (not isShortCodeAvailable(slug, ownerText)) {
            return #err("Custom slug already exists");
          };
        };
        case null {};
      };

      #ok(());
    };

    public func validateTopUp(id : Nat, caller : Principal, purchasedClicks : Nat) : Result.Result<(), Text> {
      let ?url = getUrlById(id) else return #err("URL not found");

      if (not Principal.equal(url.owner, caller)) {
        return #err("You can only top up URLs you created");
      };

      validateClickPurchase(purchasedClicks);
    };

    public func create(request : CreateRequest, owner : Principal, metadata : ?UrlMetadata) : Result.Result<Url, Text> {
      let ownerText = Principal.toText(owner);

      switch (validateCreateRequestForOwner(request, ?ownerText)) {
        case (#err(message)) return #err(message);
        case (#ok(())) {};
      };

      let shortCode = switch (request.customSlug) {
        case (?slug) {
          releaseReservationByOwnerText(ownerText);
          slug;
        };
        case null {
          switch (consumeReservedShortCode(ownerText)) {
            case (?reservedShortCode) reservedShortCode;
            case null generateShortCode();
          };
        };
      };

      let newUrl : Url = {
        id = nextId;
        originalUrl = request.originalUrl;
        shortCode = shortCode;
        clicks = 0;
        createdAt = Time.now();
        owner = owner;
        metadata = metadata;
      };

      nextId += 1;
      ignore BTree.insert(stableData.urls, Nat.compare, newUrl.id, newUrl);
      Map.add(slugToIdMap, Text.compare, shortCode, newUrl.id);
      ignore BTree.insert(
        billingStableData.allowances,
        Nat.compare,
        newUrl.id,
        {
          totalPurchasedClicks = request.purchasedClicks;
          remainingClicks = request.purchasedClicks;
          lastTopUpAt = Time.now();
        },
      );

      #ok(newUrl);
    };

    public func topUp(id : Nat, caller : Principal, purchasedClicks : Nat) : Result.Result<Url, Text> {
      switch (validateTopUp(id, caller, purchasedClicks)) {
        case (#err(message)) return #err(message);
        case (#ok(())) {};
      };

      let ?url = getUrlById(id) else return #err("URL not found");
      let allowance = ensurePersistedAllowance(id);
      let updatedAllowance : UrlAllowance = {
        totalPurchasedClicks = allowance.totalPurchasedClicks + purchasedClicks;
        remainingClicks = remainingClicksFor(url, allowance) + purchasedClicks;
        lastTopUpAt = Time.now();
      };

      ignore BTree.insert(billingStableData.allowances, Nat.compare, id, updatedAllowance);
      #ok(url);
    };

    public func delete(id : Nat, caller : Principal) : Result.Result<(), Text> {
      let ?url = BTree.get(stableData.urls, Nat.compare, id) else return #err("URL not found");

      if (not Principal.equal(url.owner, caller)) {
        return #err("You can only delete URLs you created");
      };

      ignore BTree.delete(stableData.urls, Nat.compare, id);
      ignore BTree.delete(billingStableData.allowances, Nat.compare, id);
      ignore Map.delete(slugToIdMap, Text.compare, url.shortCode);
      #ok(());
    };

    public func updateMetadata(id : Nat, caller : Principal, metadata : ?UrlMetadata) : Result.Result<Url, Text> {
      let ?url = getUrlById(id) else return #err("URL not found");

      if (not Principal.equal(url.owner, caller)) {
        return #err("You can only refresh URLs you created");
      };

      replaceMetadata(id, metadata);
    };

    public func replaceMetadata(id : Nat, metadata : ?UrlMetadata) : Result.Result<Url, Text> {
      let ?url = getUrlById(id) else return #err("URL not found");

      let updatedUrl : Url = {
        url with
        metadata = metadata;
      };

      ignore BTree.insert(stableData.urls, Nat.compare, id, updatedUrl);
      #ok(updatedUrl);
    };

    public func getUrlsMissingMetadataByOwner(owner : Principal) : [Url] {
      BTree.entries(stableData.urls)
      |> Iter.map(
        _,
        func((_, url) : (Nat, Url)) : ?Url {
          if (Principal.equal(url.owner, owner) and isMetadataMissing(url.metadata)) {
            ?url;
          } else {
            null;
          };
        },
      )
      |> Iter.filterMap(_, func(url : ?Url) : ?Url = url)
      |> Iter.toArray(_);
    };

    public func getUrlsMissingMetadata() : [Url] {
      BTree.entries(stableData.urls)
      |> Iter.map(
        _,
        func((_, url) : (Nat, Url)) : ?Url {
          if (isMetadataMissing(url.metadata)) {
            ?url;
          } else {
            null;
          };
        },
      )
      |> Iter.filterMap(_, func(url : ?Url) : ?Url = url)
      |> Iter.toArray(_);
    };

    public func toView(url : Url) : UrlView {
      let allowance = viewAllowance(url.id);
      let remainingClicks = remainingClicksFor(url, allowance);
      {
        id = url.id;
        originalUrl = url.originalUrl;
        shortCode = url.shortCode;
        clicks = url.clicks;
        createdAt = url.createdAt;
        metadata = url.metadata;
        allowance = {
          totalPurchasedClicks = allowance.totalPurchasedClicks;
          remainingClicks = remainingClicks;
          isActive = remainingClicks > 0;
        };
      };
    };

    public func toStableData() : StableData {
      {
        urls = stableData.urls;
        nextId = nextId;
      };
    };

    public func toBillingStableData() : BillingStableData {
      {
        allowances = billingStableData.allowances;
      };
    };

    public func toReservationStableData() : ReservationStableData {
      {
        reservations = reservationStableData.reservations;
      };
    };

    private func isValidUrl(url : Text) : Bool {
      Text.startsWith(url, #text("http://")) or Text.startsWith(url, #text("https://"));
    };

    private func defaultAllowance() : UrlAllowance {
      {
        totalPurchasedClicks = Pricing.minimumPurchaseClicks;
        remainingClicks = Pricing.minimumPurchaseClicks;
        lastTopUpAt = 0;
      };
    };

    private func viewAllowance(id : Nat) : UrlAllowance {
      switch (BTree.get(billingStableData.allowances, Nat.compare, id)) {
        case (?allowance) allowance;
        case null defaultAllowance();
      };
    };

    private func ensurePersistedAllowance(id : Nat) : UrlAllowance {
      switch (BTree.get(billingStableData.allowances, Nat.compare, id)) {
        case (?allowance) allowance;
        case null {
          let allowance = defaultAllowance();
          ignore BTree.insert(billingStableData.allowances, Nat.compare, id, allowance);
          allowance;
        };
      };
    };

    private func remainingClicksFor(url : Url, allowance : UrlAllowance) : Nat {
      if (allowance.totalPurchasedClicks > url.clicks) {
        allowance.totalPurchasedClicks - url.clicks;
      } else {
        0;
      };
    };

    private func isValidSlug(slug : Text) : Bool {
      if (slug.size() == 0 or slug.size() > 20) return false;

      for (char in slug.chars()) {
        let isValid = Char.isAlphabetic(char) or Char.isDigit(char) or char == '-' or char == '_';
        if (not isValid) return false;
      };
      true;
    };

    private func generateShortCode() : Text {
      pruneExpiredReservations();

      var candidateBase = nextId;

      loop {
        let code = generateShortCodeCandidate(candidateBase);
        if (isShortCodeAvailable(code, null)) {
          return code;
        };
        candidateBase += 1;
      };
    };

    private func generateShortCodeCandidate(base : Nat) : Text {
      let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
      let charsArray = chars.chars() |> Iter.toArray(_);
      let length = 6;
      var code = "";
      var num = base;

      for (i in Nat.range(0, length)) {
        let index = num % charsArray.size();
        code := code # Char.toText(charsArray[index]);
        num := num / charsArray.size() + 1;
      };

      code;
    };

    private func consumeReservedShortCode(ownerText : Text) : ?Text {
      pruneExpiredReservations();

      let ?reservation = BTree.get(reservationStableData.reservations, Text.compare, ownerText) else {
        return null;
      };

      releaseReservationByOwnerText(ownerText);
      ?reservation.shortCode;
    };

    private func pruneExpiredReservations() {
      let now = Time.now();
      let expiredOwnerTexts = Buffer.Buffer<Text>(0);

      for ((ownerText, reservation) in BTree.entries(reservationStableData.reservations)) {
        if (reservation.expiresAt <= now) {
          expiredOwnerTexts.add(ownerText);
        };
      };

      for (ownerText in expiredOwnerTexts.vals()) {
        releaseReservationByOwnerText(ownerText);
      };
    };

    private func releaseReservationByOwnerText(ownerText : Text) {
      let ?reservation = BTree.get(reservationStableData.reservations, Text.compare, ownerText) else {
        return;
      };

      ignore BTree.delete(reservationStableData.reservations, Text.compare, ownerText);
      ignore Map.delete(reservedSlugToOwnerMap, Text.compare, reservation.shortCode);
    };

    private func principalText(owner : ?Principal) : ?Text {
      switch (owner) {
        case (?principal) ?Principal.toText(principal);
        case null null;
      };
    };

    private func isShortCodeAvailable(shortCode : Text, ownerText : ?Text) : Bool {
      if (Map.get(slugToIdMap, Text.compare, shortCode) != null) {
        return false;
      };

      switch (Map.get(reservedSlugToOwnerMap, Text.compare, shortCode)) {
        case (?reservedOwnerText) {
          switch (ownerText) {
            case (?value) reservedOwnerText == value;
            case null false;
          };
        };
        case null true;
      };
    };

    private func isMetadataMissing(metadata : ?UrlMetadata) : Bool {
      switch (metadata) {
        case null true;
        case (?value) {
          not isNonEmptyText(value.title) and
          not isNonEmptyText(value.description) and
          not isNonEmptyText(value.imageUrl) and
          not isNonEmptyText(value.canonicalUrl) and
          not isNonEmptyText(value.siteName);
        };
      };
    };

    private func isNonEmptyText(value : ?Text) : Bool {
      switch (value) {
        case (?text) text != "";
        case null false;
      };
    };
  };
};
