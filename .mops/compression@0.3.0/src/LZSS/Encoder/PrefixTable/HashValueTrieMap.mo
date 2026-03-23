import P "mo:base@0/Prelude";
import I "mo:base@0/Iter";
import Hash "mo:base@0/Hash";
import List "mo:base@0/List";

import T "HashValueTrie";

module {
  type Hash = Hash.Hash;

  public class HashValueTrieMap<K, V>(hashOf : K -> Hash.Hash) {
    var map = T.empty<V>();
    var _size : Nat = 0;

    public func size() : Nat { _size };

    public func put(key : K, value : V) = ignore replace(key, value);

    public func replace(key : K, value : V) : ?V {
      let (map2, ov) = T.put<V>(map, hashOf(key), value);
      map := map2;
      switch (ov) {
        case null { _size += 1 };
        case _ {};
      };
      ov;
    };

    public func get(key : K) : ?V {
      T.find<V>(map, hashOf(key));
    };

    public func delete(key : K) = ignore remove(key);

    public func remove(key : K) : ?V {
      let (t, ov) = T.remove<V>(map, hashOf(key));
      map := t;
      switch (ov) {
        case null {};
        case (?_) { _size -= 1 };
      };
      ov;
    };

    public func keys() : I.Iter<Hash> {
      I.map(entries(), func(kv : (Hash, V)) : Hash { kv.0 });
    };

    public func vals() : I.Iter<V> {
      I.map(entries(), func(kv : (Hash, V)) : V { kv.1 });
    };

    public func entries() : I.Iter<(Hash, V)> {
      object {
        var stack = ?(map, null) : List.List<T.Trie<V>>;
        public func next() : ?(Hash, V) {
          switch stack {
            case null { null };
            case (?(trie, stack2)) {
              switch trie {
                case (#empty) {
                  stack := stack2;
                  next();
                };
                case (#leaf({ keyvals = null })) {
                  stack := stack2;
                  next();
                };
                case (#leaf({ size = c; keyvals = ?((hash, v), kvs) })) {
                  stack := ?(#leaf({ size = c - 1; keyvals = kvs }), stack2);
                  ?(hash, v);
                };
                case (#branch(br)) {
                  stack := ?(br.left, ?(br.right, stack2));
                  next();
                };
              };
            };
          };
        };
      };
    };
  };

  public func fromEntries<K, V>(
    entries : I.Iter<(K, V)>,
    keyHash : K -> Hash.Hash,
  ) : HashValueTrieMap<K, V> {
    let h = HashValueTrieMap<K, V>(keyHash);
    for ((k, v) in entries) {
      h.put(k, v);
    };
    h;
  };
};
