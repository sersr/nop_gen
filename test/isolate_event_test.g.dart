// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'isolate_event_test.dart';

// **************************************************************************
// Generator: IsolateEventGeneratorForAnnotation
// **************************************************************************

enum EventOOOneMessage { doOne, doOneWtw }
enum EventTwoTMessage { doTwoTa, doTwoParT }
enum EventTwoTthrewMessage { doTwoT, doTwoParTthrew }

abstract class IsolateMeeResolve extends IsolateTest
    with
        Resolve,
        EventoneResolve,
        EventTwoResolve,
        EventTwoTResolve,
        EventTwoTthrewResolve {
  @override
  bool resolve(m) {
    if (m is! IsolateSendMessage) return false;
    return super.resolve(m);
  }
}

abstract class IsolateMeeMessager extends IsolateTest
    with
        EventoneMessager,
        EventTwoMessager,
        EventTwoTMessager,
        EventTwoTthrewMessager {}

mixin EventoneResolve on Resolve, Eventone, EventoneOne {
  late final _eventoneResolveFuncList =
      List<DynamicCallback>.of([_doOne_0, _doOneWtw_1], growable: false);

  @override
  bool resolve(resolveMessage) {
    if (resolveMessage is IsolateSendMessage) {
      final type = resolveMessage.type;
      if (type is EventOOOneMessage) {
        if (_eventoneResolveFuncList.length > type.index) {
          send(
              _eventoneResolveFuncList
                  .elementAt(type.index)(resolveMessage.args),
              resolveMessage);
          return true;
        }
      }
    }
    return super.resolve(resolveMessage);
  }

  Stream<String?> _doOne_0(args) => doOne();
  Future<String?> _doOneWtw_1(args) => doOneWtw();
}

mixin EventoneMessager implements Eventone {
  SendEvent get send;

  @override
  Stream<String?> doOne() {
    return send.sendMessageStream(EventOOOneMessage.doOne, null);
  }

  @override
  Future<String?> doOneWtw() async {
    return send.sendMessage(EventOOOneMessage.doOneWtw, null);
  }
}

mixin EventTwoTResolve on Resolve, EventTwoT {
  late final _eventTwoTResolveFuncList =
      List<DynamicCallback>.of([_doTwoTa_0, _doTwoParT_1], growable: false);

  @override
  bool resolve(resolveMessage) {
    if (resolveMessage is IsolateSendMessage) {
      final type = resolveMessage.type;
      if (type is EventTwoTMessage) {
        if (_eventTwoTResolveFuncList.length > type.index) {
          send(
              _eventTwoTResolveFuncList
                  .elementAt(type.index)(resolveMessage.args),
              resolveMessage);
          return true;
        }
      }
    }
    return super.resolve(resolveMessage);
  }

  FutureOr<List<Map<int, String>>?> _doTwoTa_0(args) => doTwoTa();
  Future<String?> _doTwoParT_1(args) => doTwoParT(args);
}

mixin EventTwoTMessager implements EventTwoT {
  SendEvent get send;

  @override
  FutureOr<List<Map<int, String>>?> doTwoTa() async {
    return send.sendMessage(EventTwoTMessage.doTwoTa, null);
  }

  @override
  Future<String?> doTwoParT(int a) async {
    return send.sendMessage(EventTwoTMessage.doTwoParT, a);
  }
}

mixin EventTwoTthrewResolve on Resolve, EventTwoTthrew {
  late final _eventTwoTthrewResolveFuncList =
      List<DynamicCallback>.of([_doTwoT_0, _doTwoParTthrew_1], growable: false);

  @override
  bool resolve(resolveMessage) {
    if (resolveMessage is IsolateSendMessage) {
      final type = resolveMessage.type;
      if (type is EventTwoTthrewMessage) {
        if (_eventTwoTthrewResolveFuncList.length > type.index) {
          send(
              _eventTwoTthrewResolveFuncList
                  .elementAt(type.index)(resolveMessage.args),
              resolveMessage);
          return true;
        }
      }
    }
    return super.resolve(resolveMessage);
  }

  Future<String?> _doTwoT_0(args) => doTwoT();
  Future<String?> _doTwoParTthrew_1(args) => doTwoParTthrew(args);
}

mixin EventTwoTthrewMessager implements EventTwoTthrew {
  SendEvent get send;

  @override
  Future<String?> doTwoT() async {
    return send.sendMessage(EventTwoTthrewMessage.doTwoT, null);
  }

  @override
  Future<String?> doTwoParTthrew(int a) async {
    return send.sendMessage(EventTwoTthrewMessage.doTwoParTthrew, a);
  }
}

mixin EventTwoResolve on Resolve, EventTwo {}

mixin EventTwoMessager implements EventTwo {}
