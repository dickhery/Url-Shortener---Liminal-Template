/**
 * Module      : hmac.mo
 * Description : HMAC-SHA-256
 * Copyright   : 2022 Mitsunari Shigeo
 * License     : Apache 2.0 with LLVM Exception
 * Maintainer  : herumi <herumi@nifty.com>
 * Stability   : Stable
 */

import Iter "mo:core@1/Iter";
import Array "mo:core@1/Array";
import Blob "mo:core@1/Blob";
import VarArray "mo:core@1/VarArray";
import Sha256 "mo:sha2@0/Sha256";

module {
  public type HashAlgorithm = {
    #sha256;
    #custom : (Iter.Iter<Nat8>) -> Blob;
  };

  // HMAC constants as defined in RFC 2104
  private let BLOCK_SIZE : Nat = 64; // SHA-256 block size in bytes
  private let HASH_SIZE : Nat = 32; // SHA-256 output size in bytes
  private let INNER_PAD : Nat8 = 0x36; // Inner padding byte
  private let OUTER_PAD : Nat8 = 0x5c; // Outer padding byte

  /// Generates HMAC using the specified hash algorithm
  /// Implements RFC 2104: HMAC = H((K ⊕ opad) || H((K ⊕ ipad) || text))
  public func generate(
    key : [Nat8],
    msg : Iter.Iter<Nat8>,
    algorithm : HashAlgorithm,
  ) : Blob {
    // Step 1: Prepare the key (pad or hash if needed)
    let paddedKey = prepareKey(key);

    // Step 2: Create inner padded key (K ⊕ ipad)
    xorKeyWithPad(paddedKey, INNER_PAD);

    // Step 3: Compute inner hash H((K ⊕ ipad) || text)
    let innerKeyMessage = KeyMessageIterator(paddedKey, msg);
    let innerHash = Sha256.fromIter(#sha256, innerKeyMessage);

    // Step 4: Create outer padded key (K ⊕ opad)
    // Note: paddedKey currently has (K ⊕ ipad), so we XOR with (ipad ⊕ opad) to get (K ⊕ opad)
    xorKeyWithPad(paddedKey, INNER_PAD ^ OUTER_PAD);

    // Step 5: Compute final HMAC H((K ⊕ opad) || H((K ⊕ ipad) || text))
    let outerKeyAndHash = concatenateOuterKeyAndHash(paddedKey, innerHash);

    switch (algorithm) {
      case (#sha256) Sha256.fromIter(#sha256, outerKeyAndHash.vals());
      case (#custom(hasher)) hasher(outerKeyAndHash.vals());
    };
  };

  /// Prepares the key for HMAC by padding or hashing as needed
  /// Keys longer than block size are hashed, shorter keys are zero-padded
  private func prepareKey(key : [Nat8]) : [var Nat8] {
    let paddedKey = VarArray.repeat<Nat8>(0, BLOCK_SIZE);
    let keySize = key.size();

    if (keySize > BLOCK_SIZE) {
      // Key is too long, hash it first
      let hashedKey = Sha256.fromIter(#sha256, key.vals());
      for (index in hashedKey.keys()) {
        paddedKey[index] := hashedKey[index];
      };
    } else {
      // Key is acceptable length, copy it
      for (index in key.keys()) {
        paddedKey[index] := key[index];
      };
    };

    paddedKey;
  };

  /// XORs the key with the specified pad value
  private func xorKeyWithPad(key : [var Nat8], pad : Nat8) {
    for (index in key.keys()) {
      key[index] ^= pad;
    };
  };

  /// Creates an iterator that concatenates the padded key with the message
  private class KeyMessageIterator(paddedKey : [var Nat8], message : Iter.Iter<Nat8>) {
    var keyIndex = 0;

    public func next() : ?Nat8 {
      if (keyIndex < BLOCK_SIZE) {
        let result = ?paddedKey[keyIndex];
        keyIndex += 1;
        result;
      } else {
        message.next();
      };
    };
  };

  /// Concatenates the outer padded key with the inner hash result
  private func concatenateOuterKeyAndHash(outerKey : [var Nat8], innerHash : Blob) : [Nat8] {
    let combined = Array.tabulate<Nat8>(
      BLOCK_SIZE + HASH_SIZE,
      func(index : Nat) : Nat8 {
        if (index < BLOCK_SIZE) {
          outerKey[index];
        } else {
          innerHash[index - BLOCK_SIZE];
        };
      },
    );
    combined;
  };
};
