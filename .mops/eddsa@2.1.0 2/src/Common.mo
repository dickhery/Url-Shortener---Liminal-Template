import Nat "mo:core@1/Nat";
import Runtime "mo:core@1/Runtime";
import Int "mo:core@1/Int";
module {

  public type CurveKind = {
    #ed25519;
  };

  public func recoverXFromY(y : Nat, curveKind : CurveKind, isXNegative : Bool) : Nat {
    switch (curveKind) {
      case (#ed25519) {
        let p : Nat = Nat.pow(2, 255) - 19;

        let d_num : Nat = 121665;
        let d_den : Nat = 121666;

        let d_den_inv = NatUtils.modInv(d_den, p);

        var d_term1 : Nat = p - d_num;
        var d : Nat = Nat.mul(d_term1, d_den_inv) % p;

        let y_squared = NatUtils.modPow(y, 2, p);

        let numerator = (y_squared + p - 1) : Nat % p;

        let dy_squared = Nat.mul(d, y_squared) % p;
        let denominator = (1 + dy_squared) % p;

        if (Nat.equal(denominator, 0)) {
          Runtime.trap("Denominator is zero in Ed25519 point recovery.");
        };

        let denominator_inv = NatUtils.modInv(denominator, p);

        let x_squared = Nat.mul(numerator, denominator_inv) % p;

        let exponent = (p + 3) / 8;
        let x_root1 = NatUtils.modPow(x_squared, exponent, p);

        let x_root1_squared = NatUtils.modPow(x_root1, 2, p);
        if (x_root1_squared != x_squared) {
          let sqrt_minus_1 = NatUtils.modPow(2, (p - 1) / 4, p);
          let x_root1_adj = (x_root1 * sqrt_minus_1) % p;
          let x_root1_adj_squared = NatUtils.modPow(x_root1_adj, 2, p);
          if (x_root1_adj_squared != x_squared) {
            Runtime.trap("Invalid y-coordinate or calculation error: cannot find square root for x^2.");
          };

          let is_root1_adj_negative : Bool = (x_root1_adj % 2 == 1);
          if (is_root1_adj_negative == isXNegative) {
            return x_root1_adj;
          } else {
            return (p - x_root1_adj) % p;
          };
        };

        let is_root1_negative : Bool = (x_root1 % 2 == 1);

        let final_x : Nat = if (isXNegative == is_root1_negative) {
          x_root1;
        } else {
          assert (((p - x_root1) : Nat % 2 == 1) != is_root1_negative);
          (p - x_root1) % p;
        };

        return final_x;
      };
    };
  };

  module NatUtils {
    public func modPow(base : Nat, exponent : Nat, modulus : Nat) : Nat {
      if (Nat.equal(modulus, 0)) {
        Runtime.trap("modPow: Modulus cannot be zero");
      };
      if (Nat.equal(modulus, 1)) { return 0 };
      if (Nat.equal(exponent, 0)) { return 1 };

      var res : Nat = 1;
      var b : Nat = base % modulus;
      var exp : Nat = exponent;

      while (exp > 0) {
        if (exp % 2 == 1) {
          res := (res * b) % modulus;
        };
        b := (b * b) % modulus;
        exp := exp / 2;
      };
      return res;
    };

    public func modInv(a : Nat, m : Nat) : Nat {
      if (m <= 1) { Runtime.trap("modInv: Modulus must be > 1") };

      let a_reduced : Nat = a % m;
      if (Nat.equal(a_reduced, 0)) {
        Runtime.trap("modInv: Inverse does not exist (a is congruent to 0 mod m)");
      };

      let a_int : Int = a_reduced;
      let m_int : Int = m;

      let (gcd, x, _) = _extendedEuclideanAlgorithm(a_int, m_int);

      if (gcd != 1) {
        Runtime.trap("modInv: Inverse does not exist (a and m are not coprime, gcd=" # debug_show (gcd) # ")");
      };

      let result_int : Int = (x % m_int + m_int) % m_int;

      assert (result_int >= 0);
      return Int.abs(result_int);
    };

    private func _extendedEuclideanAlgorithm(a : Int, b : Int) : (Int, Int, Int) {
      if (a == 0) {
        return (b, 0, 1);
      };

      let q : Int = b / a;
      let r : Int = b % a;

      let (gcd, x1, y1) = _extendedEuclideanAlgorithm(r, a);

      let x = y1 - q * x1;
      let y = x1;

      return (gcd, x, y);
    };
  }

};
