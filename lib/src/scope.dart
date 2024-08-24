// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:collection/collection.dart';
import 'package:supply_chain/supply_chain.dart';

/// A supply scope is a container for connected nodes
class Scope {
  // ...........................................................................
  /// Creates a scope with a key. Key must be lower camel case.
  Scope({
    required this.bluePrint,
    required this.parent,
    Owner<Scope>? owner,
  })  : scm = parent!.scm,
        _owner = owner,
        assert(
          bluePrint.key.isCamelCase,
          // coverage:ignore-start
          'Key "${bluePrint.key}" must be lower camel case',
          // coverage:ignore-end
        ) {
    _init();
  }

  /// Create a root supply scope having no parent
  Scope.root({
    required String key,
    required this.scm,
  })  : parent = null,
        bluePrint = ScopeBluePrint(key: key),
        assert(key.isCamelCase) {
    _init();
  }

  /// Instantiates the scope as a meta scope
  Scope.metaScope({
    required String key,
    required this.parent,
  })  : scm = parent!.scm,
        bluePrint = ScopeBluePrint(key: key) {
    _init(isMetaScope: true);
  }

  /// Disposes the scope
  void dispose() => _dispose();

  /// Sets back all nodes to it's inital products
  void reset() {
    for (final node in _nodes.values) {
      node.reset();
    }

    for (final child in _children.values) {
      child.reset();
    }
  }

  /// Returns true if the scope is disposed
  bool get isDisposed => _isDisposed;

  /// Returns true if the scope is erased
  bool get isErased => _isErased;

  // ...........................................................................
  /// Returns the node as string
  @override
  String toString() => key;

  /// Returns true if the key matches the given key or an alias
  bool matchesKey(String key) => bluePrint.matchesKey(key);

  // ...........................................................................
  /// The supply chain manager
  final Scm scm;

  /// The key of the scope
  String get key => bluePrint.key;

  /// The blue print of the scope
  final ScopeBluePrint bluePrint;

  /// The path of the scope
  String get path => _path;

  /// The path of the scope as array
  List<String> get pathArray => _pathArray;

  /// Returns true if node matches the path
  bool matchesPath(String path) => _matchesPathArray(path.split('.'));

  /// Returns true if node matches the path
  bool matchesPathArray(List<String> pathArray) => _matchesPathArray(pathArray);

  /// The depth of the scope
  int get depth => _pathArray.length;

  /// The uinquie id of the scope
  final int id = _idCounter++;

  /// Reset id counter for test purposes
  static void testRestIdCounter() => _idCounter = 0;

  // ...........................................................................
  /// Returns the child scopes
  Iterable<Scope> get children => _children.values;

  /// Returns
  /// - empty array when depth = 0
  /// - direct children when depth = 1
  /// - direct children and children of children when depth = 2
  /// - all nodes when depth = -1
  Iterable<Scope> deepChildren({int depth = 1}) {
    if (depth == 0) {
      return [];
    }

    final result = <Scope>[...children];

    for (final child in children) {
      result.addAll(child.deepChildren(depth: depth - 1));
    }
    return result;
  }

  /// Returns
  /// - empty array when depth = 0 || parent == null
  /// - direct parent when depth = 1
  /// - parent and parent of parent when depth = 2
  /// - all parents = -1
  Iterable<Scope> deepParents({int depth = 1}) {
    if (parent == null || depth == 0) {
      return <Scope>[];
    }

    final result = <Scope>[parent!];

    final parents = parent!.deepParents(depth: depth - 1);
    result.addAll(parents);

    return result;
  }

  /// Iterable to iterate over all nodes recursively
  Iterable<Scope> get allScopes sync* {
    yield this; // Yield the current node
    for (var child in children) {
      yield* child.allScopes; // Recursively yield all children
    }
  }

  /// Returns the child scope with the given key
  Scope? child(String key) {
    for (final child in children) {
      if (child.matchesKey(key)) {
        return child;
      }
    }
    return null;
  }

  /// The parent supply scope
  Scope? parent;

  /// Returns the root scope of this scope
  Scope get root {
    var result = this;
    while (result.parent != null) {
      result = result.parent!;
    }
    return result;
  }

  /// Returns the common root of this and the other scope
  ///
  /// Throws if no common parent is found.
  Scope commonParent(Scope other) {
    if (other == this) {
      return this;
    }

    late final Scope a;
    late final Scope b;

    if (other.pathArray.length > pathArray.length) {
      a = this;
      b = other;
    } else {
      a = other;
      b = this;
    }

    var result = a;
    while (!result.isAncestorOf(b)) {
      if (result.parent == null) {
        throw ArgumentError('No common parent found.');
      }

      result = result.parent!;
    }
    return result;
  }

  /// Adds a child scope
  Scope addChild(ScopeBluePrint bluePrint) {
    return bluePrint.instantiate(scope: this);
  }

  /// Adds a number of children
  List<Scope> addChildren(List<ScopeBluePrint> bluePrints) {
    final result = <Scope>[];
    for (final bluePrint in bluePrints) {
      result.add(addChild(bluePrint));
    }

    return result;
  }

  /// Find or create a child scope with key
  Scope findOrCreateChild(String key) {
    final existingChild = child(key);
    if (existingChild != null) {
      return existingChild;
    }

    return ScopeBluePrint(key: key).instantiate(scope: this);
  }

  /// Returns true if this scope is an ancestor of the given scope
  bool isAncestorOf(Scope scope) {
    if (_children.containsKey(scope.key)) {
      return true;
    }

    for (final child in _children.values) {
      if (child.isAncestorOf(scope)) {
        return true;
      }
    }

    return false;
  }

  /// Returns true if this scope is a descendant of the given scope
  bool isDescendantOf(Scope scope) {
    if (scope._children.containsKey(key)) {
      return true;
    }

    for (final child in scope._children.values) {
      if (isDescendantOf(child)) {
        return true;
      }
    }

    return false;
  }

  // ...........................................................................
  /// Meta scopes & nodes

  /// Returns meta scopes. These scopes manage suppliers providing informations
  /// about the scope.
  Iterable<Scope> get metaScopes => _metaScopes.values;

  /// Returns the meta scope with the given key
  Scope? metaScope(String key) => _metaScopes[key];

  /// Allows to add nodes to the meta scope
  Scope metaScopeFindOrCreate(String key) {
    final existingMetaScope = metaScope(key);
    if (existingMetaScope != null) {
      return existingMetaScope;
    }

    final result = Scope.metaScope(
      key: key,
      parent: this,
    );
    _metaScopes[key] = result;
    return result;
  }

  /// Returns true if scope is a meta scope
  bool get isMetaScope => parent != null && parent!.metaScopes.contains(this);

  /// A node informing about changes in the scope or one of it's children
  late final Node<Scope> onChangeRecursive;

  /// A node informing about changes in the scope
  late final Node<Scope> onChange;

  // ...........................................................................
  /// The nodes of this scope
  Iterable<Node<dynamic>> get nodes => _nodes.values;

  /// Returns the own node for a given key or null if not found
  Node<T>? node<T>(String key) => _findItemInOwnScope<T>(
        key,
        [],
        true,
        true,
        false,
      ) as Node<T>?;

  /// Returns the node with key. If not available in scope the node is created.
  Node<T> findOrCreateNode<T>(NodeBluePrint<T> bluePrint) {
    // Return existing node when already existing
    final existingNode = _nodes[bluePrint.key];
    if (existingNode != null) {
      assert(
        existingNode.bluePrint == bluePrint,
        'Node with key "$key" already exists with different configuration',
      );
      return existingNode as Node<T>;
    }

    // Create a new node
    final node = Node<T>(
      bluePrint: bluePrint,
      scope: this,
    );

    return node;
  }

  /// Returns the node with key. If not available in scope the node is created.
  List<Node<dynamic>> findOrCreateNodes(
    List<NodeBluePrint<dynamic>> bluePrints, {
    bool applyScBuilders = true,
    Owner<Node<dynamic>>? owner,
  }) {
    final result = <Node<dynamic>>[];
    for (final bluePrint in bluePrints) {
      final newNode = bluePrint.instantiate(
        scope: this,
        applyScBuilders: true,
        owner: owner,
      );
      result.add(newNode);
    }
    return result;
  }

  /// Adds an existing node to the scope
  void addNode<T>(Node<T> node) {
    assert(node.runtimeType != Node<dynamic>);
    assert(!_isErased);

    // Reactivate the scope if it should be disposed
    _undispose();

    // Take over customers from an existing disposed node
    final existingNode = _nodes[node.key];
    if (existingNode?.isDisposed == true) {
      existingNode!.moveCustomersTo(node);
      assert(existingNode.isErased);
    }

    // Throw if node with key already exists
    else if (_nodes.containsKey(node.key)) {
      throw ArgumentError(
        'Node with key ${node.key} already exists in scope "$key"',
      );
    }

    // Save the node
    _nodes[node.key] = node;
  }

  /// Remove the node from the scope
  void removeNode(String key) {
    final node = _nodes[key];

    // Remove the node's inserts first
    node?.clearInserts();

    _nodes.remove(key);

    // Erase the scope if it is disposed and empty
    if (_isDisposed && _isEmpty) {
      _erase();
    }
  }

  /// Remove the nodes from the scope
  void removeNodes(List<NodeBluePrint<dynamic>> bluePrints) {
    for (final bluePrint in bluePrints) {
      removeNode(bluePrint.key);
    }
  }

  /// Replace an existing node with the same key
  void replaceNode(NodeBluePrint<dynamic> bluePrint) {
    final existingNode = _nodes[bluePrint.key];
    if (existingNode == null) {
      throw ArgumentError(
        'Node with key "${bluePrint.key}" does not exist in scope "$key"',
      );
    }

    existingNode.addBluePrint(bluePrint);
  }

  /// Returns true if a node with the given key exists in this or a
  /// parent supply scope
  bool hasNode(String key) {
    if (_nodes.containsKey(key)) {
      return true;
    }

    return parent?.hasNode(key) ?? false;
  }

  /// Returns the node of key in this or any parent nodes
  Node<T>? findNode<T>(
    String path, {
    bool throwIfNotFound = false,
    bool skipInserts = false,
  }) {
    return _findItem<T>(
      path,
      throwIfNotFound: throwIfNotFound,
      skipInserts: skipInserts,
      findNodes: true,
      findScopes: false,
    ) as Node<T>?;
  }

  /// Returns the first scope with the given path.
  /// Throws if multiple scopes with the same path exist.
  Scope? findChildScope(String path) {
    return _findChildScope(path.split('.'));
  }

  /// Returns the node of key in this or any parent nodes
  Scope? findScope(
    String path, {
    bool throwIfNotFound = false,
    bool skipInserts = false,
  }) {
    return _findItem<dynamic>(
      path,
      throwIfNotFound: throwIfNotFound,
      skipInserts: skipInserts,
      findNodes: false,
      findScopes: true,
    ) as Scope?;
  }

  // ...........................................................................
  /// This method is called by scopeInsert to add the insert
  void addScBuilder(ScBuilder builder) {
    _builders.add(builder);
  }

  /// Removes a scope insert
  void removeScBuilder(ScBuilder builder) {
    _builders.remove(builder);
  }

  /// Retruns the builder with given key or null if not found
  ScBuilder? builder(String key) => _builders.firstWhereOrNull(
        (element) => element.bluePrint.key == key,
      );

  /// Returns the scope inserts
  List<ScBuilder> get builders => _builders;

  // ...........................................................................
  /// Returns a graph that can be turned into svg using graphviz
  String dot({
    int childScopeDepth = -1,
    int parentScopeDepth = 0,
    List<Node<dynamic>>? highlightedNodes,
    List<Scope>? highlightedScopes,
    int dpi = Graph.defaultDpi,
  }) {
    final tree = const Graph().treeForScope(
      scope: this,
      childScopeDepth: childScopeDepth,
      parentScopeDepth: parentScopeDepth,
      highlightedNodes: highlightedNodes,
      highlightedScopes: highlightedScopes,
    );

    final dot = const Graph().dot(tree: tree, dpi: dpi);
    return dot;
  }

  /// Save the graph to a file
  ///
  /// The format can be
  /// bmp canon cgimage cmap cmapx cmapx_np dot dot_json eps exr fig gd gd2 gif
  /// gv icns ico imap imap_np ismap jp2 jpe jpeg jpg json json0 kitty kittyz
  /// mp pct pdf pic pict plain plain-ext png pov ps ps2 psd sgi svg svgz tga
  /// tif tiff tk vrml vt vt-24bit wbmp webp xdot xdot1.2 xdot1.4 xdot_json
  Future<void> writeImageFile(
    String path, {
    int childScopeDepth = -1,
    int parentScopeDepth = 0,
    List<Node<dynamic>>? highlightedNodes,
    List<Scope>? highlightedScopes,
    int dpi = Graph.defaultDpi,
    bool write2x = false,
  }) async {
    final dot = this.dot(
      childScopeDepth: childScopeDepth,
      parentScopeDepth: parentScopeDepth,
      highlightedNodes: highlightedNodes,
      highlightedScopes: highlightedScopes,
    );

    await const Graph().writeImageFile(
      dot: dot,
      path: path,
      dpi: dpi,
      write2x: write2x,
    );
  }

  // Test helpers

  // ...........................................................................
  /// Creates an example instance of Scope
  factory Scope.example({
    Scm? scm,
    String key = 'example',
    List<String> aliases = const [],
    List<ScBuilderBluePrint> builders = const [],
    List<ScopeBluePrint> children = const [],
  }) {
    scm ??= Scm.example();
    final root = Scope.root(key: 'root', scm: scm);
    final bluePrint = ScopeBluePrint(
      key: key,
      aliases: aliases,
      builders: builders,
      children: children,
    );
    final result = bluePrint.instantiate(scope: root);
    return result;
  }

  // ...........................................................................
  /// Allows to mock the content of the scope
  ///
  /// ```dart
  /// final scope = Scope.example();
  /// scope.mockContent({
  ///   'a': {
  ///     'int': 5,
  ///     'b': {
  ///       'int': 10,
  ///       'double': 3.14,
  ///       'string': 'hello',
  ///       'bool': true,
  ///       'enum': const NodeBluePrint<TestEnum>(
  ///         key: 'enum',
  ///         initialProduct: TestEnum.a,
  ///       ),
  ///     },
  ///     'c': [
  ///       const ScopeBluePrint(key: 'd'),
  ///       const ScopeBluePrint(key: 'e'),
  ///       const ScopeBluePrint(key: 'f'),
  ///     ],
  ///   },
  /// });
  ///
  /// ```
  void mockContent(Map<String, dynamic> content) {
    // Iterate all entries of the map
    for (final key in content.keys) {
      final value = content[key];

      // If the entry is a map, create a child scope
      if (value is Map<String, dynamic>) {
        // Read aliases
        final aliases = key.split('|').map(
              (e) => e.trim(),
            );
        final k = aliases.first;
        final a = aliases.skip(1).toList();

        // Create the blue print
        final bluePrint = ScopeBluePrint(
          key: k,
          aliases: a,
        );
        final child = bluePrint.instantiate(
          scope: this,
        );

        // Forward child content to child
        child.mockContent(value);
      }

      // If value is a NodeBluePrint, create a child node
      else if (value is NodeBluePrint) {
        assert(value.key == key);
        value.instantiate(scope: this);
      }

      // If value is a ScopeBluePrint, instantiate the scope
      else if (value is ScopeBluePrint) {
        assert(value.key == key);
        value.instantiate(scope: this);
      }

      // If value is a ScopeBluePrint, instantiate the scope
      else if (value is List) {
        final scope = ScopeBluePrint(key: key).instantiate(scope: this);

        for (final item in value) {
          if (item is ScopeBluePrint) {
            item.instantiate(scope: scope);
          } else {
            throw ArgumentError(
              'Lists must only contain ScopeBluePrints.',
            );
          }
        }
      }

      // If value is a basic type, create a node
      else {
        final bluePrint = switch (value.runtimeType) {
          const (int) => NodeBluePrint<int>(
              key: key,
              initialProduct: value as int,
            ),
          const (double) => NodeBluePrint<double>(
              initialProduct: value as double,
              key: key,
            ),
          const (String) => NodeBluePrint<String>(
              initialProduct: value as String,
              key: key,
            ),
          const (bool) => NodeBluePrint<bool>(
              initialProduct: value as bool,
              key: key,
            ),
          _ => throw ArgumentError(
              'Type ${value.runtimeType} not supported. '
              'Use NodeBluePrint<${value.runtimeType}> instead.',
            ),
        };

        bluePrint.instantiate(scope: this);
      }
    }
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................
  late final String _path;
  late final List<String> _pathArray;
  bool _isDisposed = false;
  bool _isErased = false;
  Owner<Scope>? _owner;

  // ...........................................................................
  final Map<String, Scope> _children = {};
  final Map<String, Scope> _metaScopes = {};
  final Map<String, Node<dynamic>> _nodes = {};
  static int _idCounter = 0;

  // ...........................................................................
  final List<ScBuilder> _builders = [];

  // ...........................................................................
  void _init({
    bool isMetaScope = false,
  }) {
    _initParent(isMetaScope);
    _initPath();
    _initMetaScopesAndNodes();
  }

  void _initParent(bool isMetaScope) {
    if (parent == null) {
      return;
    }

    // Get the container
    final container = isMetaScope ? parent!._metaScopes : parent!._children;

    // Add scope to parent scope
    container[key] = this;

    // Reactivate the parent scope if it is disposed
    parent!._undispose();
  }

  void _initPath() {
    _pathArray = parent == null ? [key] : [...parent!._pathArray, key];
    _path = parent == null ? key : '${parent!.path}.$key';
  }

  // ...........................................................................
  void _initMetaScopesAndNodes() {
    /// Meta scopes will not have meta scopes
    if (isMetaScope) {
      return;
    }

    _initOnMetaScope();
    _initOnChangeNode();
    _initOnChangeRecursiveNode();
  }

  // ...........................................................................
  void _initOnMetaScope() {
    // Adds a 'on' meta scope providing event suppliers like on.change, etc.
    Scope.metaScope(
      key: 'on',
      parent: this,
    );
  }

  // ...........................................................................
  void _dispose() {
    if (_isDisposed) {
      return;
    }

    _owner?.willDispose?.call(this);

    _isDisposed = true;

    // Dispose the scope's nodes
    for (final node in [..._nodes.values]) {
      node.dispose();
    }

    // Dispose the scope's child scopes
    for (final child in children.toList()) {
      child.dispose();
    }

    // Dispose the meta scopes
    for (final metaScope in metaScopes.toList()) {
      metaScope.dispose();
    }

    // Add the scope to the disposed scopes
    if (!_isEmpty) {
      scm.disposedItems.addScope(this);
    }

    // Erase the scope if it has no content anymore
    else {
      _erase();
    }

    _owner?.didDispose?.call(this);
  }

  // ...........................................................................
  void _erase() {
    if (_isErased) {
      return;
    }

    _owner?.willErase?.call(this);

    _isErased = true;

    // Remove the scope from its parent container
    _parentContainer.remove(key);

    // Remove the scope from the disposed scopes
    scm.disposedItems.removeScope(this);

    // Erase parent container if it is disposed and empty now
    if (parent?.isDisposed == true && parent?._isEmpty == true) {
      parent?._erase();
    }

    _owner?.didErase?.call(this);
  }

  // ...........................................................................
  void _undispose() {
    if (!isDisposed) {
      return;
    }

    _owner?.willUndispose?.call(this);

    _isDisposed = false;
    parent?._undispose();
    scm.disposedItems.removeScope(this);

    _owner?.didUndispose?.call(this);
  }

  // ...........................................................................
  Map<String, Scope> get _parentContainer =>
      isMetaScope ? parent!._metaScopes : parent!._children;

  // ...........................................................................
  void _initOnChangeNode() {
    final onScope = metaScope('on')!;

    final bluePrint = NodeBluePrint<Scope>(
      key: 'change',
      initialProduct: this,
      produce: (components, previous) => this,
    );

    onChange = bluePrint.instantiate(scope: onScope);
  }

  // ...........................................................................
  void _initOnChangeRecursiveNode() {
    final onScope = metaScope('on')!;

    final bluePrint = NodeBluePrint<Scope>(
      key: 'changeRecursive',
      initialProduct: this,
      produce: (components, previous) => this,
    );

    onChangeRecursive = bluePrint.instantiate(scope: onScope);
  }

  // ...........................................................................
  /// Returns the node of key in this or any parent nodes
  Object? _findItem<T>(
    String key, {
    bool throwIfNotFound = false,
    bool skipInserts = false,
    required bool findNodes,
    required bool findScopes,
  }) {
    // coverage:ignore-start
    if (findNodes == false && findScopes == false) {
      throw ArgumentError('findNodes and findScopes cannot be both false.');
    }

    if (findNodes && findScopes) {
      throw ArgumentError('findNodes and findScopes cannot be both true.');
    }
    // coverage:ignore-end

    final keyParts = key.split('.');
    final nodeKey = keyParts.last;
    final scopePath =
        findNodes ? keyParts.sublist(0, keyParts.length - 1) : keyParts;

    final node = _findItemInOwnScope<T>(
          nodeKey,
          scopePath,
          skipInserts,
          findNodes,
          findScopes,
        ) ??
        _findItemNodeInParentScopes<T>(
          nodeKey,
          scopePath,
          skipInserts,
          findNodes,
          findScopes,
        ) ??
        _findOneItemInChildScopes<T>(
          nodeKey,
          scopePath,
          skipInserts,
          findNodes,
          findScopes,
        ) ??
        _findItemInDirectSiblingScopes<T>(
          nodeKey,
          scopePath,
          skipInserts,
          findNodes,
          findScopes,
        ) ??
        _findItemInParentsChildScopes<T>(
          nodeKey,
          scopePath,
          skipInserts,
          findNodes,
          findScopes,
        );

    if (node == null && throwIfNotFound) {
      final item = findNodes ? 'Node' : 'Scope';
      throw ArgumentError('$item with path "$key" not found.');
    }

    return node;
  }

  // ...........................................................................
  Object? _findItemInOwnScope<T>(
    String nodeKey,
    List<String> scopePath,
    bool skipInserts,
    bool findNodes,
    bool findScopes,
  ) {
    // If path matches own scope and path segment is the last one
    // Return this scope.
    if (findScopes && scopePath.length == 1) {
      final result = child(scopePath.first) ?? _metaScopes[scopePath.first];
      return result;
    }

    // If path matches own scope and path segment is not the last one
    bool pathMatchesOwnScope =
        scopePath.isNotEmpty && matchesPathArray(scopePath);

    // If the scope path is not empty, find the child scope
    if (scopePath.isNotEmpty && !pathMatchesOwnScope) {
      final childScope = child(scopePath.first) ?? _metaScopes[scopePath.first];
      if (childScope == null) {
        return null;
      } else {
        return childScope._findItemInOwnScope<T>(
          nodeKey,
          scopePath.sublist(1),
          skipInserts,
          findNodes,
          findScopes,
        );
      }
    }

    // Return null, if we do not want to find nodes
    if (!findNodes) {
      return null;
    }

    // Find the node in the current scope
    final node = _nodes[nodeKey];
    if (node == null) {
      return null;
    }

    if (skipInserts && node.isInsert) {
      return null;
    }

    // Check if the scope matches the path
    final nodeMatchesPath = matchesPathArray(scopePath);

    if (!nodeMatchesPath) {
      return null;
    }

    if (node is! Node<T>) {
      throw ArgumentError('Node with key "$nodeKey" is not of type $T');
    }

    return node;
  }

  // ...........................................................................
  Object? _findItemNodeInParentScopes<T>(
    String key,
    List<String> scopePath,
    bool skipInserts,
    bool findNodes,
    bool findScopes,
  ) {
    return parent?._findItemInOwnScope<T>(
          key,
          scopePath,
          skipInserts,
          findNodes,
          findScopes,
        ) ??
        parent?._findItemNodeInParentScopes<T>(
          key,
          scopePath,
          skipInserts,
          findNodes,
          findScopes,
        );
  }

  // ...........................................................................
  Object? _findItemInDirectSiblingScopes<T>(
    String key,
    List<String> scopePath,
    bool skipInserts,
    bool findNodes,
    bool findScopes,
  ) {
    if (parent == null) {
      return null;
    }

    for (final sibling in parent!._children.values) {
      final node = sibling._findItemInOwnScope<T>(
        key,
        scopePath,
        skipInserts,
        findNodes,
        findScopes,
      );
      if (node != null) {
        return node;
      }
    }

    return null;
  }

  // ...........................................................................
  Object? _findOneItemInChildScopes<T>(
    String key,
    List<String> scopePath,
    bool skipInserts,
    bool findNodes,
    bool findScopes,
  ) {
    List<dynamic> result = _findMultipleNodesInChildScopes<dynamic>(
      key,
      scopePath,
      skipInserts,
      findNodes,
      findScopes,
    );

    if (result.isEmpty) {
      return null;
    } else if (result.length == 1) {
      return result.first;
    } else {
      throw ArgumentError(
        'Scope "$path": More than one node '
        'with key "$key" and Type<$T> found:\n - '
        '${result.map((e) => e.path).join('\n - ')}',
      );
    }
  }

  // ...........................................................................
  List<Object> _findMultipleNodesInChildScopes<T>(
    String key,
    List<String> scopePath,
    bool skipInserts,
    bool findNodes,
    bool findScopes,
  ) {
    final result = <Object>[];

    for (final child in _children.values) {
      final node = child._findItemInOwnScope<T>(
        key,
        scopePath,
        skipInserts,
        findNodes,
        findScopes,
      );
      if (node != null) {
        result.add(node);
      }
    }

    if (result.isNotEmpty) {
      return result;
    }

    for (final child in _children.values) {
      final nodes = child._findMultipleNodesInChildScopes<T>(
        key,
        scopePath,
        skipInserts,
        findNodes,
        findScopes,
      );
      result.addAll(nodes);
    }

    return result;
  }

  // ...........................................................................
  dynamic _findItemInParentsChildScopes<T>(
    String key,
    List<String> scopePath,
    bool skipInserts,
    bool findNodes,
    bool findScopes,
  ) {
    if (parent == null) {
      return null;
    }

    final result = parent!._findOneItemInChildScopes<T>(
      key,
      scopePath,
      skipInserts,
      findNodes,
      findScopes,
    );

    if (result != null) {
      return result;
    } else {
      return parent!._findItemInParentsChildScopes<T>(
        key,
        scopePath,
        skipInserts,
        findNodes,
        findScopes,
      );
    }
  }

  // ...........................................................................
  Scope? _findChildScope(List<String> path, {bool didFindFirstScope = false}) {
    if (path.isEmpty) {
      return null;
    }

    if (path.length == 1) {
      if (bluePrint.matchesKey(path.first)) {
        return this;
      }
      final metaScope = _metaScopes[path.first];
      if (metaScope != null) {
        return metaScope;
      }
    }

    if (path.first == key || bluePrint.matchesKey(path.first)) {
      return _findChildScope(path.sublist(1), didFindFirstScope: true);
    }

    if (didFindFirstScope) {
      final directChild = child(path.first);
      if (directChild == null) {
        return null;
      } else {
        final restPath = path.sublist(1);
        return restPath.isEmpty
            ? directChild
            : directChild._findChildScope(restPath, didFindFirstScope: true);
      }
    }

    for (final child in _children.values) {
      final result = child._findChildScope(path);
      if (result != null) {
        return result;
      }
    }

    return null;
  }

  // ...........................................................................
  bool _matchesPathArray(List<String> path) {
    Scope? parent = this;
    var i = path.length - 1;

    while (i >= 0 && parent != null) {
      final segment = path[i];
      if (!parent.matchesKey(segment)) {
        return false;
      }

      parent = parent.parent;
      i--;
    }

    return true;
  }

  // ...........................................................................
  bool get _isEmpty =>
      _nodes.isEmpty && _children.isEmpty && _metaScopes.isEmpty;
}

// #############################################################################
// Example scopes for test purposes

// .............................................................................
/// An example root scope
class ExampleScopeRoot extends Scope {
  /// Constructor
  ExampleScopeRoot({
    required super.scm,
    super.key = 'exampleRoot',
  }) : super.root() {
    findOrCreateNode(
      NodeBluePrint(
        initialProduct: 0,
        produce: (components, previous) => previous + 1, // coverage:ignore-line
        key: 'rootA',
      ),
    );

    findOrCreateNode(
      NodeBluePrint(
        initialProduct: 0,
        produce: (components, previous) => previous + 1, // coverage:ignore-line
        key: 'rootB',
      ),
    );

    ExampleChildScope(key: 'childScopeA', parent: this);
    ExampleChildScope(key: 'childScopeB', parent: this);
  }
}

// .............................................................................
/// An example child scope
class ExampleChildScope extends Scope {
  /// Constructor
  ExampleChildScope({
    required String key,
    required super.parent,
  }) : super(bluePrint: ScopeBluePrint(key: key)) {
    /// Create a node
    findOrCreateNode(
      NodeBluePrint<int>(
        initialProduct: 0,
        documentation: '<code>result = previous + 1</code>',
        produce: (components, previous) => previous + 1,
        key: 'childNodeA',
        suppliers: ['rootA', 'rootB', 'childScopeA.childNodeB'],
      ),
    );

    findOrCreateNode(
      NodeBluePrint(
        initialProduct: 0,
        documentation: '<code>result = previous + 1</code>',
        produce: (components, previous) => previous + 1,
        key: 'childNodeB',
      ),
    );

    /// Create two example child scopes
    ExampleGrandChildScope(
      key: 'grandChildScope',
      parent: this,
    );
  }
}

// .............................................................................
/// An example child scope
class ExampleGrandChildScope extends Scope {
  /// Constructor
  ExampleGrandChildScope({
    required String key,
    required super.parent,
  }) : super(bluePrint: ScopeBluePrint(key: key)) {
    findOrCreateNode(
      NodeBluePrint(
        initialProduct: 0,
        produce: (components, previous) => previous + 1,
        key: 'grandChildNodeA',
        suppliers: [
          'rootA',
        ],
      ),
    );
  }
}
