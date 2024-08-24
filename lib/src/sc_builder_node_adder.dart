// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:supply_chain/supply_chain.dart';

/// Manages the nodes added by a builder
class ScBuilderNodeAdder {
  /// The constructor
  ScBuilderNodeAdder({
    required this.builder,
  }) {
    _check();
  }

  // ...........................................................................
  /// Disposes the nodes and removes it from the scope
  void dispose() {
    for (final d in _dispose.reversed) {
      d();
    }
  }

  /// The builder this class belongs to
  final ScBuilder builder;

  /// Returns an example instance for test purposes
  static ScBuilderNodeAdder get example {
    final scope = Scope.example();

    scope.mockContent({
      'a': 1,
      'b': 2,
      'c': {
        'd': 4,
        'e': 5,
        'f': 'f',
      },
    });

    final builder = ExampleScBuilderAddingNodes().instantiate(scope: scope);
    return builder.nodeAdder;
  }

  // ...........................................................................
  /// Deeply iterate through all child nodes and replace nodes
  void applyToScope(Scope scope) {
    _applyToScope(scope);

    for (final childScope in scope.children) {
      applyToScope(childScope);
    }
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................
  void _applyToScope(Scope scope) {
    final bluePrints = builder.bluePrint.addNodes(
      hostScope: scope,
    );

    // Make sure the node does not already exist.
    for (final bluePrint in bluePrints) {
      final node = scope.node<dynamic>(bluePrint.key);
      if (node != null) {
        throw Exception(
          'Node with key "${bluePrint.key}" already exists. '
          'Please use "ScBuilderBluePrint:replaceNode" instead.',
        );
      }
    }

    // Add the nodes to the scope
    final addedNodes = scope.findOrCreateNodes(bluePrints);

    // On dispose, we will dispose also all added nodes
    _dispose.add(() {
      for (final node in addedNodes) {
        node.dispose();
      }
    });
  }

  final List<void Function()> _dispose = [];

  // ...........................................................................
  void _check() {
    final nodes = builder.bluePrint.addNodes(hostScope: ScBuilder.testScope);
    if (nodes.isNotEmpty) {
      throw Exception('ScScopeBluePrint.addNodes(hostScope) '
          'must evaluate the hostScope and not add nodes to all scopes.');
    }
  }
}

// #############################################################################
/// An example node adder for test purposes
class ExampleScBuilderAddingNodes extends ScBuilderBluePrint {
  /// The constructor
  ExampleScBuilderAddingNodes() : super(key: 'example');

  @override
  List<NodeBluePrint<dynamic>> addNodes({
    required Scope hostScope,
  }) {
    // Add k,j to example scope
    if (hostScope.key == 'example') {
      return const [
        NodeBluePrint<int>(
          key: 'k',
          initialProduct: 12,
        ),
        NodeBluePrint<int>(
          key: 'j',
          initialProduct: 367,
        ),
      ];
    }
    // Add x,y to c scope
    if (hostScope.key == 'c') {
      return const [
        NodeBluePrint<int>(
          key: 'x',
          initialProduct: 966,
        ),
        NodeBluePrint<int>(
          key: 'y',
          initialProduct: 767,
        ),
      ];
    } else {
      return []; // coverage:ignore-line
    }
  }
}
