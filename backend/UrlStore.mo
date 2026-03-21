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

module {
  public type StableData = {
    urls : BTree.BTree<Nat, Url>;
    nextId : Nat;
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

  public type UrlView = {
    id : Nat;
    originalUrl : Text;
    shortCode : Text;
    clicks : Nat;
    createdAt : Int;
    metadata : ?UrlMetadata;
  };

  public type CreateRequest = {
    originalUrl : Text;
    customSlug : ?Text;
  };

  public class Store(stableData : StableData) = self {

    var nextId = stableData.nextId;

    let slugToIdMap : Map.Map<Text, Nat> = stableData.urls
    |> BTree.entries(_)
    |> Iter.map<(Nat, Url), (Text, Nat)>(
      _,
      func((_, url) : (Nat, Url)) : (Text, Nat) = (url.shortCode, url.id),
    )
    |> Map.fromIter<Text, Nat>(_, Text.compare);

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

    public func incrementClicks(shortCode : Text) : ?Url {
      let ?url = getUrlByShortCode(shortCode) else return null;

      Debug.print("Incrementing clicks for shortCode: " # shortCode # " (ID: " # Nat.toText(url.id) # "), current clicks: " # Nat.toText(url.clicks));

      let updatedUrl : Url = {
        url with
        clicks = url.clicks + 1;
      };

      ignore BTree.insert(stableData.urls, Nat.compare, url.id, updatedUrl);
      ?updatedUrl;
    };

    public func validateCreateRequest(request : CreateRequest) : Result.Result<(), Text> {
      if (not isValidUrl(request.originalUrl)) {
        return #err("Invalid URL format: " # request.originalUrl);
      };

      switch (request.customSlug) {
        case (?slug) {
          if (not isValidSlug(slug)) {
            return #err("Invalid custom slug. Use only letters, numbers, hyphens, and underscores");
          };
          if (Map.get(slugToIdMap, Text.compare, slug) != null) {
            return #err("Custom slug already exists");
          };
        };
        case null {};
      };

      #ok(());
    };

    public func create(request : CreateRequest, owner : Principal, metadata : ?UrlMetadata) : Result.Result<Url, Text> {
      switch (validateCreateRequest(request)) {
        case (#err(message)) return #err(message);
        case (#ok(())) {};
      };

      let shortCode = switch (request.customSlug) {
        case (?slug) { slug };
        case null {
          generateShortCode();
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

      #ok(newUrl);
    };

    public func delete(id : Nat, caller : Principal) : Result.Result<(), Text> {
      let ?url = BTree.get(stableData.urls, Nat.compare, id) else return #err("URL not found");

      if (not Principal.equal(url.owner, caller)) {
        return #err("You can only delete URLs you created");
      };

      ignore BTree.delete(stableData.urls, Nat.compare, id);
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
      {
        id = url.id;
        originalUrl = url.originalUrl;
        shortCode = url.shortCode;
        clicks = url.clicks;
        createdAt = url.createdAt;
        metadata = url.metadata;
      };
    };

    public func toStableData() : StableData {
      {
        urls = stableData.urls;
        nextId = nextId;
      };
    };

    private func isValidUrl(url : Text) : Bool {
      Text.startsWith(url, #text("http://")) or Text.startsWith(url, #text("https://"));
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
      let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
      let charsArray = chars.chars() |> Iter.toArray(_);
      let length = 6;
      var code = "";
      let base = nextId;
      var num = base;

      for (i in Nat.range(0, length)) {
        let index = num % charsArray.size();
        code := code # Char.toText(charsArray[index]);
        num := num / charsArray.size() + 1;
      };

      if (Map.get(slugToIdMap, Text.compare, code) != null) {
        code # Nat.toText(nextId);
      } else {
        code;
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
