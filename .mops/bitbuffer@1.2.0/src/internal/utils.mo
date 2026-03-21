import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Int "mo:base/Int";

module {
    public func divCeil(n: Nat, d: Nat) : Nat {
        return (n + d - 1) / d;
    };

    public func int_represented_as_nat(int : Int, nbits : Nat) : Nat {
        if (int < 0) {
            let nat = Int.abs(int);
            (2 ** (nbits - 1)) + nat;
        } else {
            Int.abs(int);
        };
    };
};