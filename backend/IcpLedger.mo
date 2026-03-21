import Array "mo:core@1/Array";
import Blob "mo:core@1/Blob";
import Char "mo:core@1/Char";
import Debug "mo:core@1/Debug";
import Runtime "mo:core@1/Runtime";
import Int "mo:core@1/Int";
import Iter "mo:core@1/Iter";
import Nat "mo:core@1/Nat";
import Nat8 "mo:core@1/Nat8";
import Nat32 "mo:core@1/Nat32";
import Nat64 "mo:core@1/Nat64";
import Principal "mo:core@1/Principal";
import Result "mo:core@1/Result";
import Text "mo:core@1/Text";
import Time "mo:core@1/Time";
import VarArray "mo:core@1/VarArray";

module {
  public let ledger : Ledger = actor ("ryjl3-tyaaa-aaaaa-aaaba-cai");
  public let transferFeeE8s : Nat = 10_000;
  public let tinyUrlPriceE8s : Nat = 1_000_000;
  public let targetAccountId : Text = "91cfa92ae9d2cb6f5fe0db77f7017dff6c3f86ccca2fdf564d1348b56347be18";

  public type Tokens = { e8s : Nat64 };
  public type AccountBalanceArgs = { account : Text };
  public type TimeStamp = { timestamp_nanos : Nat64 };
  public type TransferArgs = {
    memo : Nat64;
    amount : Tokens;
    fee : Tokens;
    from_subaccount : ?Blob;
    to : Blob;
    created_at_time : ?TimeStamp;
  };
  public type TransferError = {
    #BadFee : { expected_fee : Tokens };
    #InsufficientFunds : { balance : Tokens };
    #TxTooOld : { allowed_window_nanos : Nat64 };
    #TxCreatedInFuture;
    #TxDuplicate : { duplicate_of : Nat64 };
  };
  public type TransferResult = {
    #Ok : Nat64;
    #Err : TransferError;
  };
  public type Ledger = actor {
    account_balance_dfx : shared query AccountBalanceArgs -> async Tokens;
    transfer : shared TransferArgs -> async TransferResult;
  };
  public type WalletInfo = {
    canisterPrincipal : Principal;
    depositAccountId : Text;
    subaccountHex : Text;
    balanceE8s : Nat;
    transferFeeE8s : Nat;
    tinyUrlPriceE8s : Nat;
    paymentTargetAccountId : Text;
  };

  public func subaccountForPrincipal(user : Principal) : Blob {
    let principalBytes = Blob.toArray(Principal.toBlob(user));
    let output = VarArray.tabulate<Nat8>(32, func _ = 0);
    output[0] := Nat8.fromNat(principalBytes.size());

    for (i in principalBytes.keys()) {
      if (i + 1 < 32) {
        output[i + 1] := principalBytes[i];
      };
    };

    Blob.fromVarArray(output);
  };

  public func accountIdForUser(canisterPrincipal : Principal, user : Principal) : Blob {
    Principal.toLedgerAccount(canisterPrincipal, ?subaccountForPrincipal(user));
  };

  public func toHex(blob : Blob) : Text {
    let parts = Array.map<Nat8, Text>(Blob.toArray(blob), byteToHex);
    Text.join("", parts.values());
  };

  public func getWalletInfo(canisterPrincipal : Principal, user : Principal) : async WalletInfo {
    let account = accountIdForUser(canisterPrincipal, user);
    let depositAccountId = toHex(account);
    let balance = await ledger.account_balance_dfx({ account = depositAccountId });
    {
      canisterPrincipal;
      depositAccountId;
      subaccountHex = toHex(subaccountForPrincipal(user));
      balanceE8s = Nat64.toNat(balance.e8s);
      transferFeeE8s;
      tinyUrlPriceE8s;
      paymentTargetAccountId = targetAccountId;
    };
  };

  public func hasSufficientBalance(balanceE8s : Nat) : Bool {
    balanceE8s >= tinyUrlPriceE8s + transferFeeE8s;
  };

  public func chargeForUrl(canisterPrincipal : Principal, user : Principal) : async Result.Result<(), Text> {
    await transferFromWallet(canisterPrincipal, user, targetAccountId, tinyUrlPriceE8s, ?(tinyUrlPriceE8s + transferFeeE8s));
  };

  public func withdrawFromWallet(
    canisterPrincipal : Principal,
    user : Principal,
    destinationAccountId : Text,
    amountE8s : Nat,
  ) : async Result.Result<(), Text> {
    if (amountE8s == 0) {
      return #err("Withdrawal amount must be greater than 0.");
    };

    await transferFromWallet(canisterPrincipal, user, destinationAccountId, amountE8s, ?(amountE8s + transferFeeE8s));
  };

  func transferFromWallet(
    canisterPrincipal : Principal,
    user : Principal,
    destinationAccountId : Text,
    amountE8s : Nat,
    minimumRequiredBalance : ?Nat,
  ) : async Result.Result<(), Text> {
    let walletInfo = await getWalletInfo(canisterPrincipal, user);

    switch (minimumRequiredBalance) {
      case (?requiredBalance) {
        if (walletInfo.balanceE8s < requiredBalance) {
          return #err(
            "Insufficient wallet balance. Need at least " # Nat.toText(requiredBalance) # " e8s to cover the transfer amount and ledger fee."
          );
        };
      };
      case null {};
    };

    let now = Nat64.fromNat(Int.abs(Time.now()));
    let transferArgs : TransferArgs = {
      memo = now;
      amount = { e8s = Nat64.fromNat(amountE8s) };
      fee = { e8s = Nat64.fromNat(transferFeeE8s) };
      from_subaccount = ?subaccountForPrincipal(user);
      to = hexToBlob(destinationAccountId);
      created_at_time = ?{ timestamp_nanos = now };
    };

    switch (await ledger.transfer(transferArgs)) {
      case (#Ok(_)) { #ok(()) };
      case (#Err(#InsufficientFunds({ balance }))) {
        #err("Insufficient funds. Ledger balance: " # Nat64.toText(balance.e8s) # " e8s.");
      };
      case (#Err(#BadFee({ expected_fee }))) {
        #err("Ledger transfer fee changed. Expected fee: " # Nat64.toText(expected_fee.e8s) # " e8s.");
      };
      case (#Err(#TxTooOld(_))) {
        #err("Transfer request expired before the ledger accepted it.");
      };
      case (#Err(#TxCreatedInFuture)) {
        #err("Transfer request timestamp was rejected as being too far in the future.");
      };
      case (#Err(#TxDuplicate({ duplicate_of }))) {
        Debug.print("Duplicate Tiny ICP wallet transfer detected in block " # Nat64.toText(duplicate_of));
        #ok(());
      };
    };
  };

  func byteToHex(byte : Nat8) : Text {
    let symbols = [
      "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
    ];
    let value = Nat8.toNat(byte);
    symbols[value / 16] # symbols[value % 16];
  };

  func hexToBlob(hex : Text) : Blob {
    if (hex.size() != 64) {
      Runtime.trap("Account identifier must be 64 hex characters.");
    };

    let chars = hex.chars() |> Iter.toArray(_);
    Blob.fromArray(Array.tabulate<Nat8>(32, func(index) {
      let high = hexCharToNat8(chars[index * 2]);
      let low = hexCharToNat8(chars[index * 2 + 1]);
      high * 16 + low;
    }));
  };

  func hexCharToNat8(char : Char) : Nat8 {
    let code = Char.toNat32(char);
    if (code >= 48 and code <= 57) {
      Nat8.fromNat(Nat32.toNat(code - 48));
    } else if (code >= 65 and code <= 70) {
      Nat8.fromNat(Nat32.toNat(code - 55));
    } else if (code >= 97 and code <= 102) {
      Nat8.fromNat(Nat32.toNat(code - 87));
    } else {
      Runtime.trap("Invalid hex character in account identifier.");
    };
  };
};
