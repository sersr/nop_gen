import 'dart:async';

import 'package:nop_annotations/nop_annotations.dart';
import 'package:nop_db/nop_db.dart';

part 'isolate_event_test.g.dart';

@NopIsolateEvent(resolveName: 'IsolateMee')
abstract class IsolateTest extends Eventone implements EventTwo {}

@NopIsolateEventItem(messageName: 'EventOOOne')
abstract class Eventone extends EventoneOne {
  Stream<String?> doOne();
}

abstract class EventoneOne {
  Future<String?> doOneWtw();
}

@NopIsolateEventItem(separate: true)
abstract class EventTwo extends EventTwoT implements EventTwoTthrew {}

@NopIsolateEventItem()
abstract class EventTwoT {
  FutureOr<List<Map<int, String>>?> doTwoTa();
  Future<String?> doTwoParT(int a);
}

@NopIsolateEventItem(generate: false)
abstract class EventTwoTthrew {
  Future<String?> doTwoT();
  Future<String?> doTwoParTthrew(int a);
}

class My extends IsolateMeeMessagerMain {
  @override
  Future<String?> doTwoParTthrew(int a) {
    throw UnimplementedError();
  }

  @override
  Future<String?> doTwoT() {
    throw UnimplementedError();
  }

  @override
  Future<String> doOneWtw() async {
    return '';
  }


  @override
  SendEvent get sendEvent => throw UnimplementedError();
}
