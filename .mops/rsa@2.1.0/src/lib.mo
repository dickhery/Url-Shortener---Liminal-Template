import PublicKeyModule "./PublicKey";
import SignatureModule "./Signature";
import Iter "mo:core@1/Iter";
import Result "mo:core@1/Result";

module {
  public type PublicKey = PublicKeyModule.PublicKey;

  public func PublicKey(
    e : Nat,
    n : Nat,
  ) : PublicKey = PublicKeyModule.PublicKey(e, n);

  public func publicKeyFromBytes(
    bytes : Iter.Iter<Nat8>,
    encoding : PublicKeyModule.InputByteEncoding,
  ) : Result.Result<PublicKey, Text> = PublicKeyModule.fromBytes(bytes, encoding);

  public func publicKeyFromText(
    text : Text,
    encoding : PublicKeyModule.InputTextFormat,
  ) : Result.Result<PublicKey, Text> = PublicKeyModule.fromText(text, encoding);

  public type Signature = SignatureModule.Signature;

  public func Signature(
    value : Nat,
    paddingAlgorithm : SignatureModule.PaddingAlgorithm,
  ) : Signature = SignatureModule.Signature(value, paddingAlgorithm);

  public func signatureFromBytes(
    bytes : Iter.Iter<Nat8>,
    encoding : SignatureModule.InputByteEncoding,
  ) : Result.Result<Signature, Text> = SignatureModule.fromBytes(bytes, encoding);

};
