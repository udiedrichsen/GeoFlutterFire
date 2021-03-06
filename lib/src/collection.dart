import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire/src/point.dart';
import 'util.dart';
import 'package:rxdart/rxdart.dart';

class GeoFireCollectionRef {
  Query _collectionReference;
  Stream<QuerySnapshot> _stream;

  GeoFireCollectionRef(this._collectionReference)
      : assert(_collectionReference != null) {
    _stream = _createStream(_collectionReference).shareReplay(maxSize: 1);
  }

  /// return QuerySnapshot stream
  Stream<QuerySnapshot> snapshot() {
    return _stream;
  }

  /// return the Document mapped to the [id]
  Stream<List<DocumentSnapshot>> data(String id) {
    return _stream.map((QuerySnapshot querySnapshot) {
      querySnapshot.documents.where((DocumentSnapshot documentSnapshot) {
        return documentSnapshot.documentID == id;
      });
      return querySnapshot.documents;
    });
  }

  /// add a document to collection with [data]
  Future<DocumentReference> add(Map<String, dynamic> data) {
    try {
      CollectionReference colRef = _collectionReference;
      return colRef.add(data);
    } catch (e) {
      throw Exception(
          'cannot call add on Query, use collection reference instead');
    }
  }

  /// delete document with [id] from the collection
  Future<void> delete(id) {
    try {
      CollectionReference colRef = _collectionReference;
      return colRef.document(id).delete();
    } catch (e) {
      throw Exception(
          'cannot call delete on Query, use collection reference instead');
    }
  }

  /// create or update a document with [id], [merge] defines whether the document should overwrite
  Future<void> setDoc(String id, var data, {bool merge = false}) {
    try {
      CollectionReference colRef = _collectionReference;
      return colRef.document(id).setData(data, merge: merge);
    } catch (e) {
      throw Exception(
          'cannot call set on Query, use collection reference instead');
    }
  }

  /// set a geo point with [latitude] and [longitude] using [field] as the object key to the document with [id]
  Future<void> setPoint(
      String id, String field, double latitude, double longitude) {
    try {
      CollectionReference colRef = _collectionReference;
      var point = GeoFirePoint(latitude, longitude).data;
      return colRef.document(id).setData({'$field': point}, merge: true);
    } catch (e) {
      throw Exception(
          'cannot call set on Query, use collection reference instead');
    }
  }

  /// query firestore documents based on geographic [radius] from geoFirePoint [center]
  /// [field] specifies the name of the key in the document
  Stream<List<DocumentSnapshot>> within(
      GeoFirePoint center, double radius, String field) {
    int precision = Util.setPrecision(radius);
    String centerHash = center.hash.substring(0, precision);
    List<String> area = GeoFirePoint.neighborsOf(hash: centerHash);
    area.add(centerHash);

    var queries = area.map((hash) {
      Query tempQuery = _queryPoint(hash, field);
      return _createStream(tempQuery).map((QuerySnapshot querySnapshot) {
        return querySnapshot.documents;
      });
    });

    var mergedObservable = Observable.merge(queries);

    var filtered = mergedObservable.map((List<DocumentSnapshot> list) {
      var filteredList = list.where((DocumentSnapshot doc) {
        GeoPoint geoPoint = doc.data[field]['geopoint'];
        double distance =
            center.distance(lat: geoPoint.latitude, lng: geoPoint.longitude);
        return distance <= radius * 1.02; // buffer for edge distances;
      }).map((DocumentSnapshot documentSnapshot) {
        GeoPoint geoPoint = documentSnapshot.data[field]['geopoint'];
        documentSnapshot.data['distance'] =
            center.distance(lat: geoPoint.latitude, lng: geoPoint.longitude);
        return documentSnapshot;
      }).toList();
      filteredList.sort((a, b) {
        double distA = a.data['distance'] * 1000 * 1000;
        double distB = b.data['distance'] * 1000 * 1000;
        int val = distA.toInt() - distB.toInt();
        return val;
      });
      return filteredList;
    });
    return filtered.asBroadcastStream();
  }

  /// INTERNAL FUNCTIONS

  /// construct a query for the [geoHash] and [field]
  Query _queryPoint(String geoHash, String field) {
    String end = '$geoHash~';
    Query temp = _collectionReference;
    return temp.orderBy('$field.geohash').startAt([geoHash]).endAt([end]);
  }

  /// create an observable for [ref], [ref] can be [Query] or [CollectionReference]
  Observable<QuerySnapshot> _createStream(var ref) {
    return Observable<QuerySnapshot>(ref.snapshots());
  }
}
