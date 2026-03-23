# RSA Library for Motoko

A comprehensive RSA implementation for Motoko, supporting key generation, signing, and verification with SHA-256 hashing.

## Original Project Credits

- **Original RSA Logic**: f0i (https://github.com/f0i/identify/blob/56316a8baf0d47aa2e054e879454865427d004fc/src/backend/RSA.mo)
- **License**: MIT

This project is a fork of the original RSA implementation by f0i, maintaining the same license but with additional user-friendly interfaces and packaging improvements.

## Installation

```bash
mops add rsa
```

To set up the MOPS package manager, follow the instructions from the
[MOPS Site](https://j4mwm-bqaaa-aaaam-qajbq-cai.ic0.app/)

## Quick Start

### Verify a Signature with a Public Key

```motoko
import RSA "mo:rsa";
import Iter "mo:core/Iter";
import Sha256 "mo:sha2/Sha256";

// Message to verify
let message : [Nat8] = [/* message bytes */];

// Import a public key from PEM format
let publicKeyPem = "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----";
let publicKeyResult = RSA.publicKeyFromText(publicKeyPem, #pem({
  byteEncoding = #spki;
}));

switch (publicKeyResult) {
  case (#ok(publicKey)) {
    // Import a signature
    let signatureBytes = [/* signature bytes */];
    let signature = RSA.Signature(signatureBytes);

    // Verify the signature
    let algorithm = Sha256.Algorithm.SHA256;
    let isValid = publicKey.verify(message.vals(), signature, algorithm);

    if (isValid) {
      // Signature is valid
    } else {
      // Signature is invalid
    };
  };
  case (#err(e)) { /* Handle error */ };
};
```

### Import Keys in Different Formats

```motoko
import RSA "mo:rsa";
import BaseX "mo:base-x-encoder";

// Import a public key from hex format (PKCS#1)
let publicKeyHex = "30820122..."; // Public key in hex
let publicKeyResult = RSA.publicKeyFromText(publicKeyHex, #hex({
  byteEncoding = #pkcs1;
  format = {
    prefix = #none;
    separator = #none;
  };
}));

// Import a public key from base64 format (SPKI)
let publicKeyBase64 = "MIIBIjANBgkq..."; // Base64-encoded public key
let publicKeyResult2 = RSA.publicKeyFromText(publicKeyBase64, #base64({
  byteEncoding = #spki;
}));

// Create a public key directly from modulus and exponent
let publicKey = RSA.PublicKey(
  65537, // Exponent (commonly 65537)
  123456789... // Modulus (large number)
);
```

### Exporting Keys to Different Formats

```motoko
import RSA "mo:rsa";

// Assuming you have a public key
let publicKey = /* your public key */;

// Export to PEM format (SPKI)
let pemKey = publicKey.toText(#pem({
  byteEncoding = #spki;
}));

// Export to hex format (PKCS#1)
let hexKey = publicKey.toText(#hex({
  byteEncoding = #pkcs1;
  format = {
    isUpper = false;
    prefix = #single("0x");
    separator = #none;
  };
}));

// Export to base64 format (SPKI)
let base64Key = publicKey.toText(#base64({
  byteEncoding = #spki;
  format = #standard({ includePadding = true });
}));

// Export to JWK format
let jwkKey = publicKey.toText(#jwk);
```

## API Reference

### Main Module Types and Functions

From the lib.mo file, these are the main types and functions available when you import RSA:

```motoko
// Import from bytes
public func publicKeyFromBytes(bytes : Iter.Iter<Nat8>, encoding : PublicKeyModule.InputByteEncoding) : Result.Result<PublicKey, Text>;

// Import from text
public func publicKeyFromText(text : Text, encoding : PublicKeyModule.InputTextFormat) : Result.Result<PublicKey, Text>;

// Manual Creation Functions
public func PublicKey(e : Nat, n : Nat) : PublicKey;

// Signature type
public type Signature = SignatureModule.Signature;
```

### PublicKey Methods

```motoko
// Methods on PublicKey objects
public func equal(other : PublicKey) : Bool;
public func verify(msg : Iter.Iter<Nat8>, signature : Signature, hashAlgorithm : HashAlgorithm) : Bool;
public func verifyHashed(hashedMsg : Iter.Iter<Nat8>, signature : Signature) : Bool;
public func toText(format : OutputTextFormat) : Text;
public func toBytes(encoding : OutputByteEncoding) : [Nat8];
```

### Byte and Text Format Types

```motoko
// Input byte encodings for keys
public type InputByteEncoding = {
    #spki;  // SubjectPublicKeyInfo format (X.509)
    #pkcs1; // PKCS#1 format
};

// Output byte encodings for keys
public type OutputByteEncoding = {
    #spki;  // SubjectPublicKeyInfo format (X.509)
    #pkcs1; // PKCS#1 format
};

// Input text formats for keys
public type InputTextFormat = {
    #base64 : { byteEncoding : InputByteEncoding };
    #hex : { byteEncoding : InputByteEncoding; format : BaseX.HexInputFormat };
    #pem : { byteEncoding : InputByteEncoding };
};

// Output text formats for keys
public type OutputTextFormat = {
    #base64 : { byteEncoding : OutputByteEncoding; format : BaseX.Base64OutputFormat };
    #hex : { byteEncoding : OutputByteEncoding; format : BaseX.HexOutputFormat };
    #pem : { byteEncoding : OutputByteEncoding };
    #jwk;  // JSON Web Key format
};
```

## Differences from ECDSA Library

The RSA library focuses on RSA cryptography rather than elliptic curve cryptography:

1. Different key structures:

   - RSA uses modulus (n) and exponent (e) for public keys
   - ECDSA uses x and y coordinates on an elliptic curve

2. Different verification mechanisms:

   - RSA verifies by checking if the decrypted signature hash matches the original message hash
   - ECDSA verifies using mathematical operations on the elliptic curve

3. This library primarily focuses on verification rather than signing, as it doesn't include private key generation functionality

## Dependencies

This library depends on:

- `mo:core/Iter`
- `mo:core/Nat`
- `mo:core/Nat8`
- `mo:core/Result`
- `mo:sha2`
- `mo:asn1`
- `mo:base-x-encoder`
- `mo:itertools`
- `mo:xtended-numbers`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License

This project is a fork of the original RSA implementation by f0i, maintaining the same license.
