import BpTreeModule "BpTree";
import MaxBpTreeModule "MaxBpTree";
import CmpModule "Cmp";

module {
    public let BpTree = BpTreeModule;
    public type BpTree<K, V> = BpTreeModule.BpTree<K, V>;

    public let MaxBpTree = MaxBpTreeModule;
    public type MaxBpTree<K, V> = MaxBpTreeModule.MaxBpTree<K, V>;

    public let Cmp = CmpModule;
}