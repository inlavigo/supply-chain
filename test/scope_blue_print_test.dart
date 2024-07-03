// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:supply_chain/supply_chain.dart';
import 'package:test/test.dart';

void main() {
  group('ScopeBluePrint', () {
    group('example', () {
      test('should provide a blue print with to nodes and one dependency', () {
        final scopeBluePrint = ScopeBluePrint.example();
        final dependency = scopeBluePrint.nodesFromConstructor.first;
        final subScope = scopeBluePrint.childrenFromConstructor.first;
        final node = subScope.nodesFromConstructor.first as NodeBluePrint<int>;
        final customer =
            subScope.nodesFromConstructor.last as NodeBluePrint<int>;
        expect(scopeBluePrint.toString(), scopeBluePrint.key);
        expect(dependency.key, 'dependency');
        expect(node.key, 'node');
        expect(customer.key, 'customer');
        expect(node.produce(<dynamic>[5], 0), 6);
        expect(customer.produce(<dynamic>[6], 0), 7);
      });
    });

    group('fromJson', () {
      test('should create a scope blue print from a JSON map', () {
        final json = {
          'a': {
            'int': 5,
            'double': 6.0,
            'string': 'Hello',
            'bool': true,
            'bluePrint': const NodeBluePrint<int>(
              key: 'bluePrint',
              initialProduct: 8,
            ),
            'b': {
              'c': {
                'x': 123,
              },
            },
            'c': const ScopeBluePrint(key: 'c'),
          },
        };

        final scopeBluePrint = ScopeBluePrint.fromJson(json);
        expect(scopeBluePrint.key, 'a');

        void expectNode(int i, String key, dynamic value) {
          expect(scopeBluePrint.nodesFromConstructor[i].key, key);
          expect(scopeBluePrint.nodesFromConstructor[i].initialProduct, value);
        }

        expectNode(0, 'int', 5);
        expectNode(1, 'double', 6.0);
        expectNode(2, 'string', 'Hello');
        expectNode(3, 'bool', true);
        expectNode(4, 'bluePrint', 8);

        expect(scopeBluePrint.childrenFromConstructor.length, 2);
        expect(scopeBluePrint.childrenFromConstructor.first.key, 'b');
        expect(
          scopeBluePrint
              .childrenFromConstructor.first.childrenFromConstructor.length,
          1,
        );
        expect(
          scopeBluePrint
              .childrenFromConstructor.first.childrenFromConstructor.first.key,
          'c',
        );
        expect(scopeBluePrint.childrenFromConstructor.last.key, 'c');

        expect(
          scopeBluePrint.childrenFromConstructor.first.childrenFromConstructor
              .first.nodesFromConstructor.first.key,
          'x',
        );

        expect(
          scopeBluePrint.childrenFromConstructor.first.childrenFromConstructor
              .first.nodesFromConstructor.first.initialProduct,
          123,
        );
      });

      test('should assert that the key of a node and JSON are equal', () {
        final json = {
          'a': {
            'int': const NodeBluePrint<int>(key: 'otherKey', initialProduct: 5),
          },
        };

        expect(
          () => ScopeBluePrint.fromJson(json),
          throwsA(
            isA<AssertionError>().having(
              (e) => e.toString(),
              'toString()',
              contains('The key of the node "otherKey" must be "int".'),
            ),
          ),
        );
      });

      test('should throw when in invalid type is provided', () {
        final json = {
          'a': {
            'invalid': List<int>.empty(),
          },
        };

        expect(
          () => ScopeBluePrint.fromJson(json),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'toString()',
              contains(
                'List<int>> not supported. '
                'Use NodeBluePrint<_Map<String, List<int>>> instead.',
              ),
            ),
          ),
        );
      });

      test('should assert that the key of a scope and JSON are equal', () {
        final json = {
          'a': {
            'key': const ScopeBluePrint(key: 'otherKey'),
          },
        };

        expect(
          () => ScopeBluePrint.fromJson(json),
          throwsA(
            isA<AssertionError>().having(
              (e) => e.toString(),
              'toString()',
              contains('The key of the node "otherKey" must be "key".'),
            ),
          ),
        );
      });
    });

    group('instantiate(scope)', () {
      group('should instantiate scopes and nodes returned in build()', () {
        test('when build() returns a list of scope and node overrides',
            () async {
          // Create a scope blue print
          // which overrides the with key nodeConstructedByChildScope
          const overridenScope = ScopeBluePrint(
            key: 'childScopeConstructedByParent',
            nodes: [
              NodeBluePrint<int>(
                key: 'nodeConstructedByChildScope',
                initialProduct: 6,
              ),
            ],
          );

          // Instantiate ExampleScopeBluePrint
          // and override the childScopeConstructedByParent
          final bluePrint = ExampleScopeBluePrint(
            childrenFromConstructor: [
              overridenScope,
            ],
          );

          // Instantiate the scope blue print
          final rootScope = Scope.root(key: 'root', scm: Scm.example());
          final scope = bluePrint.instantiate(scope: rootScope);

          // Check if all nodes were instantiated
          expect(
            scope.findNode<int>('parentScope.nodeBuiltByParent'),
            isNotNull,
          );

          expect(
            scope.findScope('childScopeConstructedByParent')!.bluePrint,
            overridenScope,
          );

          expect(
            scope.findNode<int>('parentScope.nodeConstructedByParent'),
            isNotNull,
          );

          // Find nodeBuiltByChildScope
          expect(
            scope.findNode<int>(
              'parentScope.childScopeBuiltByParent.nodeBuiltByChildScope',
            ),
            isNotNull,
          );

          // Find childScopeConstructedByParent
          expect(
            scope.findNode<int>(
              'parentScope.childScopeConstructedByParent.'
              'nodeConstructedByChildScope',
            ),
            isNotNull,
          );

          // Check if modifyChildNode and modifyChildScope did work
          expect(
            scope.findNode<int>('nodeToBeReplaced')!.bluePrint.initialProduct,
            807,
          );

          expect(
            scope.findScope('scopeToBeReplaced')!.bluePrint.aliases,
            ['replacedScope'],
          );

          // Write image
          await scope
              .writeImageFile('test.graphs.example_scope_blue_print.dot');
        });

        test('and apply nodesFromConstructor when provided', () {
          const replacedBluePrint = NodeBluePrint<int>(
            key: 'nodeBuiltByParent',
            initialProduct: 111,
          );

          final rootScope = Scope.example();
          final scope = ExampleScopeBluePrint(
            nodes: [replacedBluePrint],
          ).instantiate(
            scope: rootScope,
          );

          expect(
            scope.findNode<int>('parentScope.nodeBuiltByParent')!.bluePrint,
            replacedBluePrint,
          );
        });
      });

      group('should throw if blueprints contain nodes with the same key', () {
        test('when the keys are the same', () {
          const bluePrint = ScopeBluePrint(
            key: 'root',
            nodes: [
              NodeBluePrint<int>(key: 'node', initialProduct: 5),
              NodeBluePrint<int>(key: 'node', initialProduct: 6),
              NodeBluePrint<int>(key: 'node1', initialProduct: 5),
              NodeBluePrint<int>(key: 'node1', initialProduct: 6),
              NodeBluePrint<int>(key: 'node2', initialProduct: 6),
            ],
          );

          final rootScope = Scope.root(key: 'root', scm: Scm.example());
          expect(
            () => bluePrint.instantiate(scope: rootScope),
            throwsA(
              isA<ArgumentError>().having(
                (e) => e.toString(),
                'toString()',
                contains('Duplicate keys found: [node, node1]'),
              ),
            ),
          );
        });
      });
    });

    group('saveGraphToFile', () {
      test('should print a simple graph correctly', () async {
        final bluePrint = ScopeBluePrint.example();
        final parentScope = Scope.root(key: 'outer', scm: Scm.example());
        bluePrint.instantiate(
          scope: parentScope,
        );

        await parentScope.writeImageFile('test/graphs/scope_blue_print.dot');
      });
    });

    group('findNode(key)', () {
      test('should return null if no key with node is found', () {
        final bluePrint = ScopeBluePrint.example();
        final node = bluePrint.findNode<int>('Unknown');
        expect(node, isNull);
      });

      test('should return the node with the given key', () {
        final bluePrint =
            ScopeBluePrint.example().childrenFromConstructor.first;
        final node = bluePrint.findNode<int>('node');
        expect(node, isNotNull);
      });

      test('should throw if the type does not match', () {
        final bluePrint =
            ScopeBluePrint.example().childrenFromConstructor.first;

        expect(
          () => bluePrint.findNode<String>('node'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'toString()',
              contains('Node with key "node" is not of type String.'),
            ),
          ),
        );
      });
    });

    group('copyWith', () {
      group('should return a copy of the ScopeBluePrint', () {
        test('with the given key', () {
          final bluePrint = ScopeBluePrint.example();
          final copy = bluePrint.copyWith(key: 'copy');
          expect(copy.key, 'copy');
        });

        test('with the given nodes', () {
          final bluePrint = ScopeBluePrint.example();
          final copy = bluePrint.copyWith(modifiedNodes: []);
          expect(copy.nodesFromConstructor, bluePrint.nodesFromConstructor);
        });

        test('with the given subScopes', () {
          final bluePrint = ScopeBluePrint.example();
          final otherSubScopes = <ScopeBluePrint>[];
          final copy = bluePrint.copyWith(modifiedScopes: otherSubScopes);
          expect(
            copy.childrenFromConstructor,
            same(bluePrint.childrenFromConstructor),
          );
        });

        test('with the given overrides', () {
          final bluePrint =
              ScopeBluePrint.example().childrenFromConstructor.first;
          const overriddenNode = NodeBluePrint<int>(
            key: 'node',
            initialProduct: 5,
          );
          final copy = bluePrint.copyWith(modifiedNodes: [overriddenNode]);
          expect(copy.findNode<int>('node'), overriddenNode);
        });
      });
    });

    group('special cases', () {
      test('modifyChildNodes of child scopes', () {
        // Instantiate the ExampleScopeBluePrint with modifyChildNode set
        const modifiedNode = NodeBluePrint<int>(
          key: 'nodeBuiltByChildScope',
          initialProduct: 312,
        );

        final scope = ExampleScopeBluePrint(
          modifyChildNode: (scope, node) {
            if (scope.path.endsWith(
                  'childScopeBuiltByParent',
                ) &&
                node.key == 'nodeBuiltByChildScope') {
              return modifiedNode;
            } else {
              return node;
            }
          },
        ).instantiate(
          scope: Scope.example(),
        );

        final modifiedNodeOut = scope.findNode<int>('nodeBuiltByChildScope')!;
        expect(modifiedNodeOut.bluePrint, modifiedNode);
      });
    });
  });
}
