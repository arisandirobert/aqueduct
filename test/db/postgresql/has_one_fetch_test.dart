import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import '../../helpers.dart';

/*
  The test data is like so:

     A                B                C         D
     |                |                |
    C1               C2                C3
   / | \              |
  T1 V1 V2            V3
 */


void main() {
  group("Happy path", () {
    ModelContext context = null;
    List<Parent> truth;
    setUpAll(() async {
      context = await contextWithModels([Child, Parent, Toy, Vaccine]);
      truth = await populate();
    });

    tearDownAll(() async {
      await context?.persistentStore?.close();
    });

    test("Fetch has-one relationship that is null returns null for property", () async {
      var q = new Query<Parent>()
          ..matchOn.child.includeInResultSet = true
          ..matchOn.name = "D";

      var verifier = (Parent p) {
        expect(p.name, "D");
        expect(p.id, isNotNull);
        expect(p.backingMap["child"], isNull);
        expect(p.backingMap.containsKey("child"), true);
      };
      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test("Fetch has-one relationship that is null returns null for property, and more nested has relationships are ignored", () async {
      var q = new Query<Parent>()
        ..matchOn.child.includeInResultSet = true
        ..matchOn.child.toy.includeInResultSet = true
        ..matchOn.child.vaccinations.includeInResultSet = true
        ..matchOn.name = "D";

      var verifier = (Parent p) {
        expect(p.name, "D");
        expect(p.id, isNotNull);
        expect(p.backingMap["child"], isNull);
        expect(p.backingMap.containsKey("child"), true);
      };
      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test("Fetch has-one relationship that is non-null returns value for property with scalar values only", () async {
      var q = new Query<Parent>()
        ..matchOn.child.includeInResultSet = true
        ..matchOn.name = "C";

      var verifier = (Parent p) {
        expect(p.name, "C");
        expect(p.id, isNotNull);
        expect(p.child.id, isNotNull);
        expect(p.child.name, "C3");
        expect(p.child.backingMap.containsKey("toy"), false);
        expect(p.child.backingMap.containsKey("vaccinations"), false);
      };
      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test("Fetch has-one relationship, include has-one and has-many in that has-one, where bottom of graph has valid object for hasmany but not for hasone", () async {
      var q = new Query<Parent>()
        ..matchOn.child.includeInResultSet = true
        ..matchOn.child.toy.includeInResultSet = true
        ..matchOn.child.vaccinations.includeInResultSet = true
        ..matchOn.name = "B";

      var verifier = (Parent p) {
        expect(p.name, "B");
        expect(p.id, isNotNull);
        expect(p.child.id, isNotNull);
        expect(p.child.name, "C2");
        expect(p.child.backingMap.containsKey("toy"), true);
        expect(p.child.toy, isNull);
        expect(p.child.vaccinations.length, 1);
        expect(p.child.vaccinations.first.id, isNotNull);
        expect(p.child.vaccinations.first.kind, "V3");
      };

      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test("Fetch has-one relationship, include has-one and has-many in that has-one, where bottom of graph is all null/empty", () async {
      var q = new Query<Parent>()
        ..matchOn.child.includeInResultSet = true
        ..matchOn.child.toy.includeInResultSet = true
        ..matchOn.child.vaccinations.includeInResultSet = true
        ..matchOn.name = "C";

      var verifier = (Parent p) {
        expect(p.name, "C");
        expect(p.id, isNotNull);
        expect(p.child.id, isNotNull);
        expect(p.child.name, "C3");
        expect(p.child.backingMap.containsKey("toy"), true);
        expect(p.child.toy, isNull);
        expect(p.child.vaccinations, []);
      };

      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test("Fetching multiple top-level instances and including next-level hasOne", () async {
      var q = new Query<Parent>()
        ..matchOn.child.includeInResultSet = true
        ..matchOn.name = whereIn(["C", "D"]);
      var results = await q.fetch();
      expect(results.first.id, isNotNull);
      expect(results.first.name, "C");
      expect(results.first.child.name, "C3");

      expect(results.last.id, isNotNull);
      expect(results.last.name, "D");
      expect(results.last.backingMap.containsKey("child"), true);
      expect(results.last.child, isNull);
    });

    test("Fetch entire graph", () async {
      var q = new Query<Parent>()
        ..matchOn.child.includeInResultSet = true
        ..matchOn.child.toy.includeInResultSet = true
        ..matchOn.child.vaccinations.includeInResultSet = true;
      var all = await q.fetch();

      var originalIterator = truth.iterator;
      for (var p in all) {
        originalIterator.moveNext();
        expect(p.id, originalIterator.current.id);
        expect(p.name, originalIterator.current.name);
        expect(p.child?.id, originalIterator.current.child?.id);
        expect(p.child?.name, originalIterator.current.child?.name);
        expect(p.child?.toy?.id, originalIterator.current.child?.toy?.id);
        expect(p.child?.toy?.name, originalIterator.current.child?.toy?.name);

        var vacIter = originalIterator.current.child?.vaccinations?.iterator ?? <Vaccine>[].iterator;
        p?.child?.vaccinations?.forEach((v) {
          vacIter.moveNext();
          expect(v.id, vacIter.current.id);
          expect(v.kind, vacIter.current.kind);
        });
        expect(vacIter.moveNext(), false);
      }
      expect(originalIterator.moveNext(), false);
    });
  });

  group("Happy path with predicates", () {
    ModelContext context = null;

    setUpAll(() async {
      // apply predicates at various levels!!!
      context = await contextWithModels([Child, Parent, Toy, Vaccine]);
      await populate();
    });

    tearDownAll(() {
      context?.persistentStore?.close();
    });

    test("Predicate impacts top-level objects when fetching object graph", () async {
      var q = new Query<Parent>()
        ..matchOn.child.includeInResultSet = true
        ..matchOn.child.toy.includeInResultSet = true
        ..matchOn.child.vaccinations.includeInResultSet = true
        ..matchOn.name = "A";
      var results = await q.fetch();

      expect(results.length, 1);

      results.forEach((p) {
        p.child?.vaccinations?.sort((a, b) => a.id.compareTo(b.id));
      });

      var p = results.first;
      expect(p.name, "A");
      expect(p.child.name, "C1");
      expect(p.child.toy.name, "T1");
      expect(p.child.vaccinations.first.kind, "V1");
      expect(p.child.vaccinations.last.kind, "V2");
    });

    test("Predicate impacts 2nd level objects when fetching object graph", () async {
      var q = new Query<Parent>()
        ..matchOn.child.includeInResultSet = true
        ..matchOn.child.toy.includeInResultSet = true
        ..matchOn.child.vaccinations.includeInResultSet = true
        ..matchOn.child.name = "C1";
      var results = await q.fetch();

      expect(results.length, 4);

      results.forEach((p) {
        p.child?.vaccinations?.sort((a, b) => a.id.compareTo(b.id));
      });

      var p = results.first;
      expect(p.name, "A");
      expect(p.child.name, "C1");
      expect(p.child.toy.name, "T1");
      expect(p.child.vaccinations.first.kind, "V1");
      expect(p.child.vaccinations.last.kind, "V2");

      for (var other in results.sublist(1)) {
        expect(other.child, isNull);
        expect(other.backingMap.containsKey("child"), true);
      }
    });

    test("Predicate impacts 3rd level objects when fetching object graph", () async {
      var q = new Query<Parent>()
        ..matchOn.child.includeInResultSet = true
        ..matchOn.child.toy.includeInResultSet = true
        ..matchOn.child.vaccinations.includeInResultSet = true
        ..matchOn.child.vaccinations.matchOn.kind = "V1";
      var results = await q.fetch();

      expect(results.length, 4);

      var p = results.first;
      expect(p.name, "A");
      expect(p.child.name, "C1");
      expect(p.child.toy.name, "T1");
      expect(p.child.vaccinations.first.kind, "V1");
      expect(p.child.vaccinations.length, 1);

      for (var other in results.sublist(1)) {
        expect(other.child?.vaccinations ?? [], []);
      }
    });

    test("Predicate that omits top-level objects but would include lower level object return no results", () async {
      var q = new Query<Parent>()
        ..matchOn.child.includeInResultSet = true
        ..matchOn.child.toy.includeInResultSet = true
        ..matchOn.child.vaccinations.includeInResultSet = true
        ..matchOn.id = 5
        ..matchOn.child.vaccinations.matchOn.kind = "V1";

      var results = await q.fetch();
      expect(results.length, 0);
    });
  });

  group("Offhand assumptions about data", () {
    ModelContext context = null;

    setUpAll(() async {
      // apply predicates at various levels!!!
      context = await contextWithModels([Child, Parent, Toy, Vaccine]);
      await populate();
    });

    tearDownAll(() {
      context?.persistentStore?.close();
    });

    test("Objects returned in join are not the same instance", () async {
      var q = new Query<Parent>()
        ..matchOn.id = 1
        ..matchOn.child.includeInResultSet = true;

      var o = await q.fetchOne();
      expect(identical(o.child.parent, o), false);
    });
  });

  group("Bad usage cases", () {
    ModelContext context = null;

    setUpAll(() async {
      // apply predicates at various levels!!!
      context = await contextWithModels([Child, Parent, Toy, Vaccine]);
      await populate();
    });

    tearDownAll(() {
      context?.persistentStore?.close();
    });

    test("Predicate that impacts unincluded subobject is still ignored", () async {
      var q = new Query<Parent>()
        ..matchOn.child.includeInResultSet = true
        ..matchOn.child.toy.includeInResultSet = true
        ..matchOn.child.vaccinations.matchOn.kind = "V1";

      var results = await q.fetch();
      for (var p in results) {
        expect(p.child?.backingMap?.containsKey("toy") ?? true, true);
        expect(p.child?.backingMap?.containsKey("vaccinations") ?? false, false);
      }
    });
  });
}

class Parent extends Model<_Parent> implements _Parent {}
class _Parent {
  @primaryKey int id;
  String name;

  Child child;
}

class Child extends Model<_Child> implements _Child {}
class _Child {
  @primaryKey int id;
  String name;

  @RelationshipInverse(#child)
  Parent parent;

  Toy toy;

  OrderedSet<Vaccine> vaccinations;
}

class Toy extends Model<_Toy> implements _Toy {}
class _Toy {
  @primaryKey int id;

  String name;

  @RelationshipInverse(#toy)
  Child child;
}

class Vaccine extends Model<_Vaccine> implements _Vaccine {}
class _Vaccine {
  @primaryKey int id;
  String kind;

  @RelationshipInverse(#vaccinations)
  Child child;
}

Future<List<Parent>> populate() async {
  var modelGraph = <Parent>[];
  var parents = [
    new Parent()
      ..name = "A"
      ..child = (new Child()
        ..name = "C1"
        ..toy = (new Toy()..name = "T1")
        ..vaccinations = (new OrderedSet<Vaccine>.from([
          new Vaccine()..kind = "V1",
          new Vaccine()..kind = "V2",
        ]))),

    new Parent()
      ..name = "B"
      ..child = (new Child()
        ..name = "C2"
        ..vaccinations = (new OrderedSet<Vaccine>.from([
          new Vaccine()..kind = "V3"
        ]))),

    new Parent()
      ..name = "C"
      ..child = (new Child()..name = "C3"),

    new Parent()
      ..name = "D"
  ];

  for (var p in parents) {
    var q = new Query<Parent>()
      ..values.name = p.name;
    var insertedParent = await q.insert();
    modelGraph.add(insertedParent);

    if (p.child != null) {
      var childQ = new Query<Child>()
        ..values.name = p.child.name
        ..values.parent = insertedParent;
      insertedParent.child = await childQ.insert();

      if (p.child.toy != null) {
        var toyQ = new Query<Toy>()
          ..values.name = p.child.toy.name
          ..values.child = insertedParent.child;
        insertedParent.child.toy = await toyQ.insert();
      }

      if (p.child.vaccinations != null) {
        insertedParent.child.vaccinations = new OrderedSet<Vaccine>.from(await Future.wait(p.child.vaccinations.map((v) {
          var vQ = new Query<Vaccine>()
            ..values.kind = v.kind
            ..values.child = insertedParent.child;
          return vQ.insert();
        })));
      }
    }
  }

  return modelGraph;
}