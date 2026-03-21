# EdDSA Library for Motoko

A comprehensive EdDSA (Ed25519) implementation for Motoko, supporting public key operations, signature verification, and multiple encoding formats.

## Original Project Credits

- **Original Ed25519 Logic**: f0i (https://github.com/f0i/identify/blob/56316a8baf0d47aa2e054e879454865427d004fc/src/backend/Ed25519.mo)
- **License**: MIT

This project is a fork of the original Ed25519 implementation by f0i, maintaining the same license but with additional user-friendly interfaces and packaging improvements.

## Installation

```bash
mops add eddsa
```

To set up the MOPS package manager, follow the instructions from the
[MOPS Site](https://j4mwm-bqaaa-aaaam-qajbq-cai.ic0.app/)

## Quick Start

### Verify a Signature with a Public Key

```motoko
import EdDSA "mo:eddsa";
import Iter "mo:core/Iter";

// Message to verify
let message : [Nat8] = [/* message bytes */];

// Import a public key from PEM format
let publicKeyPem = "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----";
let publicKeyResult = EdDSA.publicKeyFromText(publicKeyPem, #pem({
  byteEncoding = #spki;
}));

switch (publicKeyResult) {
  case (#ok(publicKey)) {
    // Import a signature
    let signatureText = "b31effd71522fb03e1f932d5f4e2115b43f5ae9d793407c752a36b49373399539000dc10cf0ee2695c143df1ce7976102f50c8d999e365522e9b656db63b990f";
    let signatureResult = EdDSA.signatureFromText(signatureText, #hex({
      byteEncoding = #raw({ curve = #ed25519 });
      format = { prefix = #none };
    }));

    switch (signatureResult) {
      case (#ok(signature)) {
        // Verify the signature
        let isValid = publicKey.verify(message.vals(), signature);

        if (isValid) {
          // Signature is valid
        } else {
          // Signature is invalid
        };
      };
      case (#err(e)) { /* Handle error */ };
    };
  };
  case (#err(e)) { /* Handle error */ };
};
```

### Import Public Keys in Different Formats

```motoko
import EdDSA "mo:eddsa";
import BaseX "mo:base-x-encoder";

// Import a public key from hex format (raw bytes)
let publicKeyHex = "e9f2dcb6bbfb9fbd41d984490265cb624918c3b0eb16b1b30cfeea656a243360";
let publicKeyResult = EdDSA.publicKeyFromText(publicKeyHex, #hex({
  byteEncoding = #raw({ curve = #ed25519 });
  format = {
    prefix = #none;
  };
}));

// Import a public key from base64 format (SPKI)
let publicKeyBase64 = "MCowBQYDK2VwAyEA6fLca7v7n71B2YRJAmXLYkkYw7DrFrGzDP7qZWokM2A=";
let publicKeyResult2 = EdDSA.publicKeyFromText(publicKeyBase64, #base64({
  byteEncoding = #spki;
}));

// Create a public key directly from x and y coordinates
let publicKey = EdDSA.PublicKey(
  51286398080436808364751719791652616808950448576822237245355328773964350987914, // x
  43512393995653313780034091491436412746798652980930200433568831129039272735465, // y
  #ed25519 // curve
);
```

### Import Signatures in Different Formats

```motoko
import EdDSA "mo:eddsa";

// Import a signature from hex format (raw bytes)
let signatureHex = "b31effd71522fb03e1f932d5f4e2115b43f5ae9d793407c752a36b49373399539000dc10cf0ee2695c143df1ce7976102f50c8d999e365522e9b656db63b990f";
let signatureResult = EdDSA.signatureFromText(signatureHex, #hex({
  byteEncoding = #raw({ curve = #ed25519 });
  format = {
    prefix = #none;
  };
}));

// Import a signature from base64 format (raw bytes)
let signatureBase64 = "szH/1xUi+wPh+TLV9OIRW0P1rp15NAfHUqNrSTczmVOQANwQzw7iaVwUPfHOeXYQL1DI2ZnjZVIum2VttjuZDw==";
let signatureResult2 = EdDSA.signatureFromText(signatureBase64, #base64({
  byteEncoding = #raw({ curve = #ed25519 });
}));

// Import a signature from DER encoding
let signatureDER = "..."; // DER-encoded signature in base64 or hex
let signatureResult3 = EdDSA.signatureFromText(signatureDER, #base64({
  byteEncoding = #der({ curve = #ed25519 });
}));

// Create a signature directly from components
let signature = EdDSA.Signature(
  32659244743902125671750775541108600435972519608980791545566174304356588384442, // x
  37812647512915033038667227002500228956020200491405235946433044056539611995827, // y
  7055432450925680840815035157730575267673472388327113095507987779099519877264 // s
);
```

### Exporting Keys and Signatures to Different Formats

```motoko
import EdDSA "mo:eddsa";

// Assuming you have a public key and signature
let publicKey = /* your public key */;
let signature = /* your signature */;

// Export public key to different formats
let rawHexKey = publicKey.toText(#hex({
  byteEncoding = #raw;
  format = {
    isUpper = false;
    prefix = #none;
  };
}));

let spkiPemKey = publicKey.toText(#pem({
  byteEncoding = #spki;
}));

let base64Key = publicKey.toText(#base64({
  byteEncoding = #raw;
  format = #url({ includePadding = false });
}));

let jwkKey = publicKey.toText(#jwk);

// Export signature to different formats
let rawHexSig = signature.toText(#hex({
  byteEncoding = #raw;
  format = {
    isUpper = false;
    prefix = #none;
  };
}));

let derBase64Sig = signature.toText(#base64({
  byteEncoding = #der;
  format = #standard({ includePadding = true });
}));

let pemSig = signature.toText(#pem({
  byteEncoding = #raw;
}));

let jwkSig = signature.toText(#jwk);
```

## API Reference

### Main Module Types and Functions

From the lib.mo file, these are the main types and functions available when you import EdDSA:

```motoko
// Public key creation and import
public func PublicKey(
  x : Nat,
  y : Nat,
  curveKind : CurveKind,
) : PublicKey;

public func publicKeyFromBytes(
  bytes : Iter.Iter<Nat8>,
  encoding : PublicKeyInputByteEncoding,
) : Result.Result<PublicKey, Text>;

public func publicKeyFromText(
  text : Text,
  encoding : PublicKeyInputTextFormat,
) : Result.Result<PublicKey, Text>;

// Signature creation and import
public func Signature(
  x : Int,
  y : Nat,
  s : Nat,
) : Signature;

public func signatureFromBytes(
  bytes : Iter.Iter<Nat8>,
  encoding : SignatureInputByteEncoding,
) : Result.Result<Signature, Text>;

public func signatureFromText(
  text : Text,
  encoding : SignatureInputTextFormat,
) : Result.Result<Signature, Text>;

// Type definitions
public type CurveKind = { #ed25519 };
public type PublicKey = PublicKeyModule.PublicKey;
public type Signature = SignatureModule.Signature;
public type PublicKeyInputByteEncoding = PublicKeyModule.InputByteEncoding;
public type PublicKeyOutputByteEncoding = PublicKeyModule.OutputByteEncoding;
public type PublicKeyInputTextFormat = PublicKeyModule.InputTextFormat;
public type PublicKeyOutputTextFormat = PublicKeyModule.OutputTextFormat;
public type SignatureInputByteEncoding = SignatureModule.InputByteEncoding;
public type SignatureOutputByteEncoding = SignatureModule.OutputByteEncoding;
public type SignatureInputTextFormat = SignatureModule.InputTextFormat;
public type SignatureOutputTextFormat = SignatureModule.OutputTextFormat;
```

### PublicKey Methods

```motoko
// Methods on PublicKey objects
public func equal(other : PublicKey) : Bool;
public func verify(msg : Iter.Iter<Nat8>, signature : Signature) : Bool;
public func toText(format : OutputTextFormat) : Text;
public func toBytes(encoding : OutputByteEncoding) : [Nat8];
```

### Signature Methods

```motoko
// Methods on Signature objects
public func equal(other : Signature) : Bool;
public func toText(format : OutputTextFormat) : Text;
public func toBytes(encoding : OutputByteEncoding) : [Nat8];
```

### Byte and Text Format Types

```motoko
// PublicKey byte encodings
public type PublicKeyInputByteEncoding = {
    #raw : { curve : CurveKind };
    #spki;
};

public type PublicKeyOutputByteEncoding = {
    #raw;
    #spki;
};

// Signature byte encodings
public type SignatureInputByteEncoding = {
    #raw : { curve : CurveKind };
    #der : { curve : CurveKind };
};

public type SignatureOutputByteEncoding = {
    #raw;
    #der;
};

// Text formats (common to both public keys and signatures)
public type InputTextFormat = {
    #base64 : { byteEncoding : InputByteEncoding };
    #hex : { byteEncoding : InputByteEncoding; format : BaseX.HexInputFormat };
    #pem : { byteEncoding : InputByteEncoding };
};

public type OutputTextFormat = {
    #base64 : { byteEncoding : OutputByteEncoding; format : BaseX.Base64OutputFormat };
    #hex : { byteEncoding : OutputByteEncoding; format : BaseX.HexOutputFormat };
    #pem : { byteEncoding : OutputByteEncoding };
    #jwk;
};
```

## License

MIT License

This project is a fork of the original Ed25519 implementation by f0i, maintaining the same license.
