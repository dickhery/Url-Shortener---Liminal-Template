import PublicKeyModule "./PublicKey";
import SignatureModule "./Signature";
import Iter "mo:core@1/Iter";
import Result "mo:core@1/Result";

module {
  public type PublicKey = PublicKeyModule.PublicKey;
  public type Signature = SignatureModule.Signature;

  // Re-export types for convenient access
  public type PublicKeyInputByteEncoding = PublicKeyModule.InputByteEncoding;
  public type PublicKeyOutputByteEncoding = PublicKeyModule.OutputByteEncoding;
  public type PublicKeyInputTextFormat = PublicKeyModule.InputTextFormat;
  public type PublicKeyOutputTextFormat = PublicKeyModule.OutputTextFormat;

  public type SignatureInputByteEncoding = SignatureModule.InputByteEncoding;
  public type SignatureOutputByteEncoding = SignatureModule.OutputByteEncoding;
  public type SignatureInputTextFormat = SignatureModule.InputTextFormat;
  public type SignatureOutputTextFormat = SignatureModule.OutputTextFormat;

  public type CurveKind = PublicKeyModule.CurveKind;

  // Create a public key from raw coordinates
  public func PublicKey(
    x : Nat,
    y : Nat,
    curveKind : PublicKeyModule.CurveKind,
  ) : PublicKey = PublicKeyModule.PublicKey(x, y, curveKind);

  // Import public key from bytes
  public func publicKeyFromBytes(
    bytes : Iter.Iter<Nat8>,
    encoding : PublicKeyModule.InputByteEncoding,
  ) : Result.Result<PublicKey, Text> = PublicKeyModule.fromBytes(bytes, encoding);

  // Import public key from text
  public func publicKeyFromText(
    text : Text,
    encoding : PublicKeyModule.InputTextFormat,
  ) : Result.Result<PublicKey, Text> = PublicKeyModule.fromText(text, encoding);

  // Create a signature from raw values
  public func Signature(
    x : Int,
    y : Nat,
    s : Nat,
  ) : Signature = SignatureModule.Signature(x, y, s);

  // Import signature from bytes
  public func signatureFromBytes(
    bytes : Iter.Iter<Nat8>,
    encoding : SignatureModule.InputByteEncoding,
  ) : Result.Result<Signature, Text> = SignatureModule.fromBytes(bytes, encoding);

  // Import signature from text
  public func signatureFromText(
    text : Text,
    encoding : SignatureModule.InputTextFormat,
  ) : Result.Result<Signature, Text> = SignatureModule.fromText(text, encoding);
};
