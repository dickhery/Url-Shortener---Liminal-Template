import Hash "mo:base@0/Hash";

import List "mo:base@0/List";
import AssocList "mo:base@0/AssocList";

module {

  let MAX_LEAF_SIZE = 8;

  public type Trie<V> = {
    #empty;
    #leaf : Leaf<V>;
    #branch : Branch<V>;
  };

  type Hash = Hash.Hash;

  public type Leaf<V> = {
    size : Nat;
    keyvals : AssocList<Hash, V>;
  };

  public type Branch<V> = {
    size : Nat;
    left : Trie<V>;
    right : Trie<V>;
  };

  public type AssocList<H, V> = AssocList.AssocList<H, V>;

  type List<T> = List.List<T>;

  public func equal_hash(h1 : Hash, h2 : Hash) : Bool {
    h1 == h2;
  };

  public func empty<V>() : Trie<V> { #empty };

  public func size<V>(t : Trie<V>) : Nat {
    switch t {
      case (#empty) { 0 };
      case (#leaf(l)) { l.size };
      case (#branch(b)) { b.size };
    };
  };

  public func branch<V>(l : Trie<V>, r : Trie<V>) : Trie<V> {
    let sum = size(l) + size(r);
    #branch {
      size = sum;
      left = l;
      right = r;
    };
  };

  public func leaf<V>(kvs : AssocList<Hash, V>, bitpos : Nat) : Trie<V> {
    fromList(null, kvs, bitpos);
  };

  module ListUtil {
    /* Deprecated: List.lenClamp */
    public func lenClamp<T>(l : List<T>, max : Nat) : ?Nat {
      func rec(l : List<T>, max : Nat, i : Nat) : ?Nat {
        switch l {
          case null { ?i };
          case (?(_, t)) {
            if (i >= max) { null } else { rec(t, max, i + 1) };
          };
        };
      };
      rec(l, max, 0);
    };
  };

  public func fromList<V>(kvc : ?Nat, kvs : AssocList<Hash, V>, bitpos : Nat) : Trie<V> {
    func rec(kvc : ?Nat, kvs : AssocList<Hash, V>, bitpos : Nat) : Trie<V> {
      switch kvc {
        case null {
          switch (ListUtil.lenClamp(kvs, MAX_LEAF_SIZE)) {
            case null {} /* fall through to branch case. */;
            case (?len) {
              return #leaf({ size = len; keyvals = kvs });
            };
          };
        };
        case (?c) {
          if (c == 0) {
            return #empty;
          } else if (c <= MAX_LEAF_SIZE) {
            return #leaf({ size = c; keyvals = kvs });
          } else {

          };
        };
      };
      let (ls, l, rs, r) = splitList(kvs, bitpos);
      if (ls == 0 and rs == 0) {
        #empty;
      } else if (rs == 0 and ls <= MAX_LEAF_SIZE) {
        #leaf({ size = ls; keyvals = l });
      } else if (ls == 0 and rs <= MAX_LEAF_SIZE) {
        #leaf({ size = rs; keyvals = r });
      } else {
        branch(rec(?ls, l, bitpos + 1), rec(?rs, r, bitpos + 1));
      };
    };
    rec(kvc, kvs, bitpos);
  };

  public func replace<V>(t : Trie<V>, hash : Hash, v : ?V) : (Trie<V>, ?V) {
    func rec(t : Trie<V>, bitpos : Nat) : (Trie<V>, ?V) {
      switch t {
        case (#empty) {
          let (kvs, _) = AssocList.replace(null, hash, equal_hash, v);
          (leaf(kvs, bitpos), null);
        };
        case (#branch(b)) {
          let bit = Hash.bit(hash, bitpos);
          if (not bit) {
            let (l, v_) = rec(b.left, bitpos + 1);
            (branch(l, b.right), v_);
          } else {
            let (r, v_) = rec(b.right, bitpos + 1);
            (branch(b.left, r), v_);
          };
        };
        case (#leaf(l)) {
          let (kvs2, old_val) = AssocList.replace(l.keyvals, hash, equal_hash, v);
          (leaf(kvs2, bitpos), old_val);
        };
      };
    };
    let (to, vo) = rec(t, 0);
    (to, vo);
  };

  public func put<V>(t : Trie<V>, hash : Hash, v : V) : (Trie<V>, ?V) {
    replace(t, hash, ?v);
  };

  public func find<V>(t : Trie<V>, hash : Hash) : ?V {
    func rec(t : Trie<V>, bitpos : Nat) : ?V {
      switch t {
        case (#empty) { null };
        case (#leaf(l)) {
          AssocList.find<Hash, V>(l.keyvals, hash, equal_hash);
        };
        case (#branch(b)) {
          let bit = Hash.bit(hash, bitpos);
          if (not bit) {
            rec(b.left, bitpos + 1);
          } else {
            rec(b.right, bitpos + 1);
          };
        };
      };
    };
    rec(t, 0);
  };

  func splitList<V>(l : AssocList<Hash, V>, bitpos : Nat) : (Nat, AssocList<Hash, V>, Nat, AssocList<Hash, V>) {
    func rec(l : AssocList<Hash, V>) : (Nat, AssocList<Hash, V>, Nat, AssocList<Hash, V>) {
      switch l {
        case null { (0, null, 0, null) };
        case (?((hash, v), t)) {
          let (cl, l, cr, r) = rec(t);
          if (not Hash.bit(hash, bitpos)) {
            (cl + 1, ?((hash, v), l), cr, r);
          } else { (cl, l, cr + 1, ?((hash, v), r)) };
        };
      };
    };
    rec(l);
  };

  public func remove<V>(t : Trie<V>, hash : Hash) : (Trie<V>, ?V) {
    replace(t, hash, null);
  };
};
