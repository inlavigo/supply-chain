// @license
// Copyright (c) 2019 - 2023 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:supply_chain/supply_chain.dart';

/// A supplier delivers products to a node
typedef Supplier<T> = Node<T>;

/// A customer receives products to a node
typedef Customer<T> = Node<T>;

/// A worker is a node on the assembly line
typedef Worker<T> = Node<T>;

/// Produce delegate
typedef Produce<T> = T Function(
  List<dynamic> components,
  T previousProduct,
);

/// A node in a scope
class Node<T> {
  // ...........................................................................

  /// - [initialProduct]: The product delivered before [produce] is called the
  ///   first time
  /// - [produce]: A function producing the product and saving it in product.
  ///   Important: Call node.reportUpdate() after production.
  /// - [hasUpdates]: Is called after the product has been updated
  /// - [needsUpdates]: Is called when the product needs to be updated
  /// - [scope]: The scope the node belongs to
  /// - [key]: The key of the node
  /// - [cacheSize]: The number of items in the cache

  Node({
    required NodeBluePrint<T> bluePrint,
    required this.scope,
  })  : scm = scope.scm,
        _product = bluePrint.initialProduct,
        assert(bluePrint.key.isCamelCase),
        _bluePrint = bluePrint {
    _init();
  }

  // ...........................................................................
  /// Disposes the node
  void dispose() {
    _isDisposed = true;
    for (final d in _dispose.reversed) {
      d();
    }
    _dispose.clear();
  }

  /// Returns true if node is disposed
  bool get isDisposed => _isDisposed;

  // ...........................................................................
  /// Updates the node with a new bluePrint
  void update(NodeBluePrint<T> bluePrint) {
    final oldBluePrint = this.bluePrint;

    if (bluePrint == oldBluePrint) {
      return;
    }

    assert(bluePrint.key == this.bluePrint.key);

    // Update the bluePrint
    this._bluePrint = bluePrint;

    // If the produce function has changed, we need to produce again
    if (bluePrint.produce != oldBluePrint.produce) {
      scm.nominate(this);
    }
  }

  // ...........................................................................
  /// The configuration of this node
  NodeBluePrint<T> get bluePrint => _bluePrint;

  // ...........................................................................
  // Identification
  /// The key of the node
  String get key => bluePrint.key;

  /// The key of the node
  String get path => '${scope.path}.$key';

  /// The unique id of the node
  final int id = _idCounter++;

  /// Returns the key of the node
  @override
  String toString() {
    return key;
  }

  // ...........................................................................
  // Product

  /// The product of the node
  T get product => _product;

  /// The product of the node
  set product(T v) {
    assert(
      bluePrint.produce == doNothing<T>,
      'Product can only be set if bluePrint.produce is doNothing',
    );
    _product = v;
    scm.nominate(this);
  }

  // ...........................................................................
  // Animation

  /// Returns true if node is animated
  bool get isAnimated => _isAnimated;

  /// Assign true if node is animated. Node will be nominated on every frame.
  set isAnimated(bool v) {
    if (_isAnimated == v) {
      return;
    }

    _isAnimated = v;

    if (v) {
      scm.animateNode(this);
    } else {
      scm.deanimateNode(this);
    }
  }

  // ...........................................................................
  // Preparation

  /// Returns true if node and its customers need to be prepared for production
  bool needsPreparation() {
    /// If new priority is higher then current one, a new preparation is needed
    return !isStaged;
  }

  /// Prepares the node for production with a given priority
  void prepare() {
    this.isStaged = true;
  }

  /// Returns true, if node is not staged
  bool get isReady => !isStaged;

  /// Is ready to produce when all suppliers are ready
  bool get isReadyToProduce {
    for (final supplier in suppliers) {
      if (!supplier.isReady) {
        return false;
      }
    }
    return true;
  }

  // ...........................................................................
  // Priority

  /// The node's own priority.
  Priority get ownPriority => _ownPriority;

  /// Changes node's own priority
  set ownPriority(Priority p) {
    _ownPriority = p;
    scm.priorityHasChanged(this);
  }

  /// SCM uses this to assign the highest customer priority
  Priority? customerPriority;

  /// The used priority. Is the highest priority of node and its customers
  Priority get priority =>
      (customerPriority != null && customerPriority!.value > ownPriority.value)
          ? customerPriority!
          : ownPriority;

  // ...........................................................................
  // Production

  /// The product produced by this node
  T _product;

  /// Produces the product.
  void produce({bool announce = true}) {
    assert(!isDisposed);

    final newProduct =
        bluePrint.produce(suppliers.map((s) => s.product).toList(), product);

    _product = newProduct;
    if (announce) {
      scm.hasNewProduct(this);
    }
  }

  /// Returns true, if node is staged for production
  bool isStaged = false;

  /// Finalizes production
  void finalizeProduction() {
    this.isStaged = false;
  }

  // ...........................................................................
  // Suppliers

  /// The suppliers of the node
  Iterable<Node<dynamic>> get suppliers => _suppliers;

  /// Add a supplier to the node
  void addSupplier(Supplier<dynamic> supplier) => _addSupplier(supplier);

  /// Remove a supplier from the node
  void removeSupplier(Supplier<dynamic> supplier) => _removeSupplier(supplier);

  // ...........................................................................
  // Customers

  /// The customers of the node
  Iterable<Node<dynamic>> get customers => _customers;

  /// Add a customer to the node
  void addCustomer(Customer<dynamic> customer) => _addCustomer(customer);

  /// Remove a customer from the node
  void removeCustomer(Customer<dynamic> customer) => _removeCustomer(customer);

  // ...........................................................................
  // Deep suppliers & customers

  /// Get suppliers of the node of a given depth
  Iterable<Node<dynamic>> deepSuppliers({int depth = 1}) {
    if (depth < 0) depth = 100000;

    if (depth == 0) {
      return [];
    }

    final result = <Node<dynamic>>[...suppliers];

    for (final supplier in suppliers) {
      result.addAll(supplier.deepSuppliers(depth: depth - 1));
    }
    return result;
  }

  /// Get suppliers of the node of a given depth
  Iterable<Node<dynamic>> deepCustomers({int depth = 1}) {
    if (depth == 0) {
      return [];
    }

    final result = <Node<dynamic>>[...customers];

    for (final customer in customers) {
      result.addAll(customer.deepCustomers(depth: depth - 1));
    }
    return result;
  }

  // ...........................................................................
  // Timeouts

  /// Is set to true if production times out
  bool isTimedOut = false;

  /// Milliseconds showing the production start time.
  Duration productionStartTime = Duration.zero;

  // ...........................................................................
  /// Example node for test purposes
  static Node<int> example({
    NodeBluePrint<int>? bluePrint,
    Scope? scope,
  }) {
    scope ??= Scope.example(scm: Scm.testInstance);
    bluePrint ??= NodeBluePrint.example();

    final result = Node<int>(
      bluePrint: bluePrint,
      scope: scope,
    );

    // Realtime nodes will produce immediately
    result.ownPriority = Priority.realtime;

    return result;
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................

  /// Reset Id counter for tests
  static void testResetIdCounter() => _idCounter = 0;

  static int _idCounter = 0;

  // ...........................................................................
  // Init & Dispose
  void _init() {
    _initScope();
    _initScm();
  }

  // ...........................................................................
  void _initScm() {
    scm.addNode(this);
    scm.needsInitSuppliers(this);
    _dispose.add(() {
      scm.removeNode(this);

      // Cleanup suppliers
      for (final supplier in [...suppliers]) {
        removeSupplier(supplier);
      }

      // Cleanup customers
      for (final customer in [...customers]) {
        removeCustomer(customer);
      }
    });
  }

  // ...........................................................................
  void _initScope() {
    scope.addNode(this);
    _dispose.add(() {
      scope.removeNode(this.key);
    });
  }

  // ...........................................................................
  /// The supply chain manager
  final Scm scm;

  /// The chain this node belongs to
  final Scope scope;

  /// The common scope of two nodes
  Scope commonParent(Node<dynamic> other) {
    return scope.commonParent(other.scope);
  }

  // ...........................................................................
  // Graph
  /// Save the graph to a file
  ///
  /// The format can be
  /// bmp canon cgimage cmap cmapx cmapx_np dot dot_json eps exr fig gd gd2 gif
  /// gv icns ico imap imap_np ismap jp2 jpe jpeg jpg json json0 kitty kittyz
  /// mp pct pdf pic pict plain plain-ext png pov ps ps2 psd sgi svg svgz tga
  /// tif tiff tk vrml vt vt-24bit wbmp webp xdot xdot1.2 xdot1.4 xdot_json
  Future<void> saveGraphToFile(
    String path, {
    int childScopeDepth = 0,
    int parentScopeDepth = 0,
    int supplierDepth = -1,
    int customerDepth = 0,
    bool highLightNode = false,
  }) async {
    await const Graph().writeNodeToFile(
      this,
      childScopeDepth: childScopeDepth,
      parentScopeDepth: parentScopeDepth,
      supplierDepth: supplierDepth,
      customerDepth: customerDepth,
      path,
      highLightNode: highLightNode,
    );
  }

  // ...........................................................................
  /// Returns a graph that can be turned into svg using graphviz
  String graph({
    int childScopeDepth = 0,
    int parentScopeDepth = 0,
    int supplierDepth = -1,
    int customerDepth = 0,
  }) {
    return const Graph().fromNode(
      this,
      childScopeDepth: childScopeDepth,
      parentScopeDepth: parentScopeDepth,
      supplierDepth: -supplierDepth,
      customerDepth: customerDepth,
    );
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................
  final List<void Function()> _dispose = [];

  bool _isDisposed = false;

  // ...........................................................................
  NodeBluePrint<T> _bluePrint;

  // ...........................................................................
  Priority _ownPriority = Priority.frame;

  // ...........................................................................
  final List<Supplier<dynamic>> _suppliers = [];
  final List<Customer<dynamic>> _customers = [];

  // ...........................................................................
  void _addSupplier(Supplier<dynamic> supplier) {
    // Supplier<T> already added? Do nothing.
    if (_suppliers.contains(supplier)) {
      return;
    }

    // Add supplier to list of suppliers
    _suppliers.add(supplier);

    // This producer becomes a customer of its supplier
    supplier.addCustomer(this);

    // Because we have new dependencies, a rebuild is needed
    scm.nominate(this);
  }

  // ...........................................................................
  void _removeSupplier(Supplier<dynamic> supplier) {
    if (!_suppliers.contains(supplier)) {
      return;
    }

    _suppliers.remove(supplier);
    supplier.removeCustomer(this);
    if (!isDisposed) {
      scm.nominate(this);
    }
  }

  // ...........................................................................
  void _addCustomer(Customer<dynamic> customer) {
    if (_customers.contains(customer)) {
      return;
    }

    _customers.add(customer);
    customer.addSupplier(this);
  }

  // ...........................................................................
  void _removeCustomer(Customer<dynamic> customer) {
    if (!_customers.contains(customer)) {
      return;
    }

    _customers.remove(customer);
    customer.removeSupplier(this);
  }

  // ...........................................................................
  // Tick & Animation
  bool _isAnimated = false;
}

/// Provides a deeply configured node sructure
class ButterFlyExample {
  /// Constructor
  ButterFlyExample({bool withScopes = false}) {
    final scope = Scope.example(scm: Scm.example(), key: 'butterFly');

    if (withScopes) {
      scope.mockContent({
        'level3': {
          's111': 's111',
          'level2': {
            's11': 's11',
            's10': 's10',
            's01': 's01',
            's00': 's00',
            'level1': {
              's1': 's1',
              's0': 's0',
              'level0': {
                'x': 'x',
              },
              'c0': 'c0',
              'c1': '1',
            },
            'c00': 'c00',
            'c01': 'c01',
            'c10': 'c10',
            'c11': 'c11',
          },
          'c111': 'c111',
        },
      });
    } else {
      scope.mockContent({
        's111': 's111',
        's11': 's11',
        's10': 's10',
        's01': 's01',
        's00': 's00',
        's1': 's1',
        's0': 's0',
        'x': 'x',
        'c0': 'c0',
        'c1': '1',
        'c00': 'c00',
        'c01': 'c01',
        'c10': 'c10',
        'c11': 'c11',
        'c111': 'c111',
      });
    }

    s111 = scope.findNode<String>('s111')!;
    s11 = scope.findNode<String>('s11')!;
    s10 = scope.findNode<String>('s10')!;
    s01 = scope.findNode<String>('s01')!;
    s00 = scope.findNode<String>('s00')!;
    s1 = scope.findNode<String>('s1')!;
    s0 = scope.findNode<String>('s0')!;
    x = scope.findNode<String>('x')!;
    c0 = scope.findNode<String>('c0')!;
    c1 = scope.findNode<String>('c1')!;
    c00 = scope.findNode<String>('c00')!;
    c01 = scope.findNode<String>('c01')!;
    c10 = scope.findNode<String>('c10')!;
    c11 = scope.findNode<String>('c11')!;
    c111 = scope.findNode<String>('c111')!;

    s11.addSupplier(s111);
    s1.addSupplier(s11);
    s1.addSupplier(s10);
    s0.addSupplier(s01);
    s0.addSupplier(s00);
    x.addSupplier(s1);
    x.addSupplier(s0);
    x.addCustomer(c0);
    x.addCustomer(c1);
    c0.addCustomer(c00);
    c0.addCustomer(c01);
    c1.addCustomer(c10);
    c1.addCustomer(c11);
    c11.addCustomer(c111);
  }

  /// s111
  late final Node<String> s111;

  /// s11
  late final Node<String> s11;

  /// s10
  late final Node<String> s10;

  /// s01
  late final Node<String> s01;

  /// s00
  late final Node<String> s00;

  /// s1
  late final Node<String> s1;

  /// s0
  late final Node<String> s0;

  /// x
  late final Node<String> x;

  /// c0
  late final Node<String> c0;

  /// c1
  late final Node<String> c1;

  /// c00
  late final Node<String> c00;

  /// c01
  late final Node<String> c01;

  /// c10
  late final Node<String> c10;

  /// c11
  late final Node<String> c11;

  /// c111
  late final Node<String> c111;
}
