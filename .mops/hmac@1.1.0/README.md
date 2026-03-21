# HMAC library for Motoko

A fork of [herumi/ecdsa-motoko](https://github.com/herumi/ecdsa-motoko), providing HMAC-256 implementation.

## Original Project Credits

- **Author**: MITSUNARI Shigeo (herumi@nifty.com)
- **Original Repository**: https://github.com/herumi/ecdsa-motoko

## License

Apache 2.0 with LLVM Exception

This project is a fork of the original ECDSA implementation by MITSUNARI Shigeo, maintaining the same license.

## Installation

```bash
mops install hmac
```

To setup MOPS package manage, follow the instructions from the
[MOPS Site](https://j4mwm-bqaaa-aaaam-qajbq-cai.ic0.app/)

## API Reference

```motoko
// Generate HMAC digest
public func generate(
    key : [Nat8],              // Key for HMAC
    msg : Iter.Iter<Nat8>,     // Message to hash
    algorithm : HashAlgorithm, // Hash algorithm to use
) : Blob                       // Returns HMAC digest as Blob

// Define available hash algorithms
public type HashAlgorithm = {
    #sha256;                                  // Standard SHA-256
    #custom : (Iter.Iter<Nat8>) -> Blob;      // Custom hash function
};
```

## Changes from Original

Adapted it to use for the MOPS package manager

## Original Project

If you'd like to support the original project:

- Original repository: https://github.com/herumi/ecdsa-motoko
- [GitHub Sponsor](https://github.com/sponsors/herumi)
