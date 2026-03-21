import Nat "mo:core@1/Nat";
import Nat8 "mo:core@1/Nat8";
import NatX "mo:xtended-numbers@2/NatX";
import Sha256 "mo:sha2@0/Sha256";
import Iter "mo:core@1/Iter";
import Result "mo:core@1/Result";
import ASN1 "mo:asn1@3";

module {
  public type OutputByteEncoding = {
    #raw;
  };

  public type InputByteEncoding = {
    #raw : {
      paddingAlgorithm : PaddingAlgorithm;
    };
  };

  public type HashAlgorithm = Sha256.Algorithm;
  public type PaddingAlgorithm = {
    #pkcs1v1_5;
    // #pss; TODO
  };

  public class Signature(
    value_ : Nat,
    paddingAlgorithm_ : PaddingAlgorithm,
  ) {
    public let value = value_;
    public let paddingAlgorithm = paddingAlgorithm_;

    public func equal(other : Signature) : Bool {
      return value == other.value;
    };

    public func getHashValue(
      exponent : Nat,
      modulus : Nat,
    ) : Result.Result<[Nat8], Text> {
      // RSA decryption (signature verification)
      let sigDecrypted = modExp(value, exponent, modulus);

      // Convert decrypted signature to bytes
      let decryptedBytes = NatX.toNatBytes(sigDecrypted, #msb);

      // Use ASN.1 library to decode the PKCS#1 v1.5 formatted data
      switch (paddingAlgorithm_) {
        case (#pkcs1v1_5) switch (decodePKCS1Signature(decryptedBytes.vals())) {
          case (#err(e)) return #err("Failed to decode PKCS#1 v1.5 signature: " # e);
          case (#ok((hashBytes, _))) #ok(hashBytes);
        };
      };

    };

    // Convert signature to bytes array (big-endian)
    public func toBytes(encoding : OutputByteEncoding) : [Nat8] {
      switch (encoding) {
        case (#raw) NatX.toNatBytes(value, #msb);
      };
    };
  };

  public func fromBytes(
    bytes : Iter.Iter<Nat8>,
    encoding : InputByteEncoding,
  ) : Result.Result<Signature, Text> {
    switch (encoding) {
      case (#raw({ paddingAlgorithm })) {
        let ?nat = NatX.fromNatBytes(bytes, #msb) else return #err("Failed to decode signature");
        #ok(Signature(nat, paddingAlgorithm));
      };
    };
  };

  // Modular exponentiation (a^b mod n)
  private func modExp(base : Nat, exp : Nat, mod : Nat) : Nat {
    var result : Nat = 1;
    var power : Nat = base % mod;
    var exponent : Nat = exp;

    while (exponent > 0) {
      if (exponent % 2 == 1) {
        result := (result * power) % mod;
      };
      exponent := exponent / 2;
      power := (power * power) % mod;
    };

    return result;
  };

  // Helper function to decode PKCS#1 v1.5 signature and extract the hash
  private func decodePKCS1Signature(bytesIter : Iter.Iter<Nat8>) : Result.Result<([Nat8], HashAlgorithm), Text> {
    // Expected format: 0x01 || PS (0xFF...) || 0x00 || DigestInfo (ASN.1 DER)

    // 1. Check the first byte for the block type (0x01)
    let firstByteOpt = bytesIter.next();
    switch (firstByteOpt) {
      case null { return #err("Input byte iterator is empty") };
      case (?byte) {
        if (byte != 0x01) {
          // Consider using Nat8.toHex or similar for better error message if available
          return #err("Invalid PKCS#1 v1.5 signature format: expected 0x01 as the first byte, got 0x" # Nat8.toText(byte));
        };
      };
    };

    // 2. Skip padding bytes (0xFF), looking for the 0x00 separator
    var paddingBytesSkipped : Nat = 0;
    var foundSeparator = false;
    label f loop {
      let nextByteOpt = bytesIter.next();
      switch (nextByteOpt) {
        case null {
          // Reached end without finding the 0x00 separator
          return #err("Invalid PKCS#1 v1.5 padding: reached end of input before 0x00 separator");
        };
        case (?byte) {
          if (byte == 0xFF) {
            paddingBytesSkipped += 1;
            // Continue loop to consume next byte
          } else if (byte == 0x00) {
            // Found the separator
            foundSeparator := true;
            break f; // Exit loop
          } else {
            // Found an unexpected byte within the padding area
            return #err("Invalid PKCS#1 v1.5 padding: unexpected byte 0x" # Nat8.toText(byte) # " found before 0x00 separator");
          };
        };
      };
    };

    // Ensure the separator was actually found (loop could theoretically exit otherwise if logic changes)
    if (not foundSeparator) {
      // This case should technically be unreachable with the current loop structure, but good practice
      return #err("Internal error: Loop exited without finding 0x00 separator");
    };

    // 3. Check minimum padding length
    // PKCS#1 v1.5 requires at least 8 bytes of padding (0xFF)
    if (paddingBytesSkipped < 8) {
      return #err("Invalid PKCS#1 v1.5 padding: less than 8 padding bytes found (" # Nat.toText(paddingBytesSkipped) # ")");
    };

    // At this point, bytesIter is positioned right after the 0x00 separator,
    // ready to read the ASN.1 DER encoded DigestInfo.

    // 4. Decode the DigestInfo using ASN.1 library
    // Pass the *remaining* iterator. ASN1.decodeDER needs to handle potential partial reads
    // or you might need to collect the rest of the iterator into a Blob/Array first if the decoder requires it.
    let digestInfoResult = ASN1.fromBytes(bytesIter, #der);

    let digestInfo = switch (digestInfoResult) {
      case (#err(msg)) {
        return #err("Failed to decode DigestInfo: " # msg);
      };
      case (#ok(val)) { val }; // `val` should be the decoded ASN.1 structure
    };

    // 5. Parse the DigestInfo structure
    // DigestInfo ::= SEQUENCE {
    //    digestAlgorithm AlgorithmIdentifier,
    //    digest OCTET STRING
    // }
    // AlgorithmIdentifier ::= SEQUENCE { algorithm OBJECT IDENTIFIER, parameters ANY DEFINED BY algorithm OPTIONAL }

    let #sequence(digestInfoSeq) = digestInfo else {
      return #err("Decoded DigestInfo is not a SEQUENCE");
    };

    if (digestInfoSeq.size() != 2) {
      return #err("DigestInfo SEQUENCE should have 2 elements, found " # Nat.toText(digestInfoSeq.size()));
    };

    // 5a. Parse AlgorithmIdentifier
    let #sequence(algorithmSeq) = digestInfoSeq[0] else {
      return #err("Algorithm identifier (DigestInfo element 0) is not a SEQUENCE");
    };

    // Must have at least the OID, optionally parameters
    if (algorithmSeq.size() < 1 or algorithmSeq.size() > 2) {
      return #err("Algorithm identifier SEQUENCE has invalid size: " # Nat.toText(algorithmSeq.size()));
    };

    let #objectIdentifier(algorithmOid) = algorithmSeq[0] else {
      return #err("Algorithm identifier SEQUENCE element 0 is not an OID");
    };

    // 5b. Identify the Hash Algorithm from OID
    let algorithm = if (algorithmOid == [2, 16, 840, 1, 101, 3, 4, 2, 1]) {
      // Use a helper for robust comparison
      #sha256;
    } else {
      // Consider a more detailed OID formatting function if available
      return #err("Unsupported hash algorithm OID: " # debug_show (algorithmOid));
    };

    // Optional: Check ASN.1 parameters (e.g., SHA family usually uses NULL or omits them)
    if (algorithmSeq.size() == 2) {
      switch (algorithmSeq[1]) {
        case (#null_) (); // NULL parameters are standard for SHA OIDs
        case (_) return #err("Unexpected parameters for hash algorithm"); // Stricter
      };
    };

    // 5c. Extract the Hash Value
    let #octetString(hash) = digestInfoSeq[1] else {
      return #err("Digest value (DigestInfo element 1) is not an OCTET STRING");
    };

    // Optional, but recommended: Verify hash length matches algorithm
    let expectedLen = switch (algorithm) {
      case (#sha256) { 32 };
    };
    if (hash.size() != expectedLen) {
      return #err(
        "Extracted hash length (" # Nat.toText(hash.size())
        # ") does not match expected length (" # Nat.toText(expectedLen)
        # ") for algorithm " # debug_show (algorithm)
      );
    };

    // Optional: Check if the iterator has been fully consumed by the ASN.1 decoder
    if (bytesIter.next() != null) {
      return #err("Trailing data found after decoding DigestInfo");
    };

    // 6. Return success
    return #ok((hash, algorithm));
  };

};
