import Nat "mo:core@1/Nat";

module {
  public let clickBundleSize : Nat = 10_000;
  public let clickBundlePriceE8s : Nat = 10_000_000;
  public let minimumPurchaseClicks : Nat = clickBundleSize;
  public let minimumPurchaseCostE8s : Nat = clickBundlePriceE8s;

  public func isValidClickPurchase(clicks : Nat) : Bool {
    clicks >= minimumPurchaseClicks and clicks % clickBundleSize == 0;
  };

  public func priceForClicks(clicks : Nat) : Nat {
    (clicks / clickBundleSize) * clickBundlePriceE8s;
  };
};
