import Nat "mo:core@1/Nat";
import Nat8 "mo:core@1/Nat8";
import Iter "mo:core@1/Iter";
import Result "mo:core@1/Result";
import ASN1 "mo:asn1@3";
import Sha256 "mo:sha2@0/Sha256";
import Int "mo:core@1/Int";
import Text "mo:core@1/Text";
import Runtime "mo:core@1/Runtime";
import Signature "./Signature";
import BaseX "mo:base-x-encoder@2";
import PeekableIter "mo:xtended-iter@1/PeekableIter";
import NatX "mo:xtended-numbers@2/NatX";

module {
  public type HashAlgorithm = Sha256.Algorithm;

  public type InputByteEncoding = {
    #spki;
    #pkcs1;
  };

  public type OutputByteEncoding = {
    #spki;
    #pkcs1;
  };

  public type OutputTextFormat = {
    #base64 : {
      byteEncoding : OutputByteEncoding;
      format : BaseX.Base64OutputFormat;
    };
    #hex : {
      byteEncoding : OutputByteEncoding;
      format : BaseX.HexOutputFormat;
    };
    #pem : {
      byteEncoding : OutputByteEncoding;
    };
    #jwk;
  };

  public type InputTextFormat = {
    #base64 : {
      byteEncoding : InputByteEncoding;
    };
    #hex : {
      byteEncoding : InputByteEncoding;
      format : BaseX.HexInputFormat;
    };
    #pem : {
      byteEncoding : InputByteEncoding;
    };
  };

  let RSA_OID = [1, 2, 840, 113549, 1, 1, 1];

  public class PublicKey(
    exponent_ : Nat,
    modulus_ : Nat,
  ) {
    public let exponent = exponent_;
    public let modulus = modulus_;

    public func equal(other : PublicKey) : Bool {
      return exponent == other.exponent and modulus == other.modulus;
    };

    // Verify a message signature using this public key
    public func verify(
      msg : Iter.Iter<Nat8>,
      signature : Signature.Signature,
      hashAlgorithm : HashAlgorithm,
    ) : Bool {
      // Hash the message
      let hashedMsg = Sha256.fromIter(hashAlgorithm, msg);
      verifyHashed(hashedMsg.vals(), signature);
    };

    public func verifyHashed(
      hashedMsg : Iter.Iter<Nat8>,
      signature : Signature.Signature,
    ) : Bool {
      let hashBytes = switch (signature.getHashValue(exponent, modulus)) {
        case (#err(e)) Runtime.trap("Failed to get hash value: " # e);
        case (#ok(hashBytes)) hashBytes;
      };
      let hashBytesIter = hashBytes.vals();
      for (byte in hashedMsg) {
        let otherByte = hashBytesIter.next();
        if (?byte != otherByte) {
          return false;
        };
      };
      hashBytesIter.next() == null; // Ensure all bytes were consumed
    };

    // Export public key in PKCS#1 format
    public func toBytes(encoding : OutputByteEncoding) : [Nat8] {
      switch (encoding) {
        case (#pkcs1) ASN1.toBytes(#sequence([#integer(modulus), #integer(exponent)]), #der);
        case (#spki) {
          let pkcs1Bytes = toBytes(#pkcs1);

          // Create ASN.1 structure for SPKI
          let spki : ASN1.ASN1Value = #sequence([
            #sequence([
              #objectIdentifier(RSA_OID),
              #null_,
            ]),
            #bitString({
              data = pkcs1Bytes;
              unusedBits = 0;
            }),
          ]);

          ASN1.toBytes(spki, #der);
        };
      };
    };

    public func toText(format : OutputTextFormat) : Text {
      switch (format) {
        case (#hex(hex)) {
          let bytes = toBytes(hex.byteEncoding);
          BaseX.toHex(bytes.vals(), hex.format);
        };
        case (#base64(base64)) {
          let bytes = toBytes(base64.byteEncoding);
          BaseX.toBase64(bytes.vals(), base64.format);
        };
        case (#pem({ byteEncoding })) {
          let bytes = toBytes(byteEncoding);
          let keyType = switch (byteEncoding) {
            case (#spki) ("PUBLIC");
            case (#pkcs1) ("RSA PUBLIC");
          };
          let base64 = BaseX.toBase64(bytes.vals(), #standard({ includePadding = true }));

          let iter = PeekableIter.fromIter(base64.chars());
          var formatted = Text.fromIter(Iter.take(iter, 64));
          while (iter.peek() != null) {
            formatted #= "\n" # Text.fromIter(Iter.take(iter, 64));
          };

          "-----BEGIN " # keyType # " KEY-----\n" # formatted # "\n-----END " # keyType # " KEY-----\n";
        };
        case (#jwk) {
          // Convert modulus and exponent to BigEndian byte arrays
          let nBytes = NatX.toNatBytes(modulus, #msb);
          let nB64 = BaseX.toBase64(nBytes.vals(), #url({ includePadding = false }));
          let eBytes = NatX.toNatBytes(exponent, #msb);
          let eB64 = BaseX.toBase64(eBytes.vals(), #url({ includePadding = false }));

          // Format as JWK JSON
          "{\"kty\":\"RSA\",\"n\":\"" # nB64 # "\",\"e\":\"" # eB64 # "\"}";
        };
      };
    };
  };

  // Create a public key from PKCS#1 encoded data
  public func fromBytes(bytes : Iter.Iter<Nat8>, encoding : InputByteEncoding) : Result.Result<PublicKey, Text> {
    let asn1 = switch (ASN1.fromBytes(bytes, #der)) {
      case (#err(msg)) #err("Failed to decode PKCS#1 data: " # msg);
      case (#ok(asn1)) asn1;
    };
    switch (encoding) {
      case (#pkcs1) {
        let #sequence(seq) = asn1 else {
          return #err("PKCS#1 data is not a SEQUENCE");
        };

        if (seq.size() != 2) {
          return #err("PKCS#1 SEQUENCE should have 2 elements");
        };

        let #integer(modulus) = seq[0] else {
          return #err("Modulus is not an INTEGER");
        };

        let #integer(exponent) = seq[1] else {
          return #err("Exponent is not an INTEGER");
        };

        #ok(PublicKey(Int.abs(exponent), Int.abs(modulus)));
      };
      case (#spki) {
        let #sequence(seq) = asn1 else {
          return #err("SPKI data is not a SEQUENCE");
        };

        if (seq.size() != 2) {
          return #err("SPKI SEQUENCE should have 2 elements");
        };

        // Check algorithm identifier
        let #sequence(algoSeq) = seq[0] else {
          return #err("Algorithm identifier is not a SEQUENCE");
        };

        if (algoSeq.size() < 1) {
          return #err("Algorithm identifier SEQUENCE is empty");
        };

        let #objectIdentifier(algoOid) = algoSeq[0] else {
          return #err("Algorithm identifier does not contain an OID");
        };

        if (algoOid != RSA_OID) {
          return #err("Unsupported algorithm: not RSA");
        };

        // Extract key data
        let #bitString(keyData) = seq[1] else {
          return #err("Key data is not a BIT STRING");
        };

        fromBytes(keyData.data.vals(), #pkcs1);
      };
    };
  };

  public func fromText(value : Text, format : InputTextFormat) : Result.Result<PublicKey, Text> {
    switch (format) {
      case (#hex({ format; byteEncoding })) {
        // Convert hex to bytes
        switch (BaseX.fromHex(value, format)) {
          case (#ok(bytes)) {
            switch (fromBytes(bytes.vals(), byteEncoding)) {
              case (#ok(key)) #ok(key);
              case (#err(e)) #err("Invalid key bytes: " # e);
            };
          };
          case (#err(e)) #err("Invalid hex format: " # e);
        };
      };

      case (#base64({ byteEncoding })) {
        // Convert base64 to bytes
        switch (BaseX.fromBase64(value)) {
          case (#ok(bytes)) {
            switch (fromBytes(bytes.vals(), byteEncoding)) {
              case (#ok(key)) #ok(key);
              case (#err(e)) #err("Invalid key bytes: " # e);
            };
          };
          case (#err(e)) #err("Invalid base64 format: " # e);
        };
      };

      case (#pem({ byteEncoding })) {
        let keyType = switch (byteEncoding) {
          case (#spki) "PUBLIC";
          case (#pkcs1) "RSA PUBLIC";
        };
        // Parse PEM format
        switch (extractPEMContent(value, keyType)) {
          case (#ok(base64Content)) {
            switch (BaseX.fromBase64(base64Content)) {
              case (#ok(bytes)) {
                switch (fromBytes(bytes.vals(), byteEncoding)) {
                  case (#ok(key)) #ok(key);
                  case (#err(e)) #err("Invalid key bytes: " # e);
                };
              };
              case (#err(e)) #err("Failed to decode PEM base64: " # e);
            };
          };
          case (#err(e)) #err(e);
        };
      };
    };
  };

  // Helper function to extract content from PEM format for public keys
  private func extractPEMContent(pem : Text, keyType : Text) : Result.Result<Text, Text> {
    let header = "-----BEGIN " # keyType # " KEY-----";
    let ?headerTrimmedPem = Text.stripStart(pem, #text(header)) else return #err("Invalid PEM format: missing header " # header);
    let footer = "-----END " # keyType # " KEY-----\n";
    let ?trimmedPem = Text.stripEnd(headerTrimmedPem, #text(footer)) else return #err("Invalid PEM format: missing footer " # footer);
    #ok(Text.join("", Text.split(trimmedPem, #char('\n'))));
  };
};
