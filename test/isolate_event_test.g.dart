// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'isolate_event_test.dart';

// **************************************************************************
// Generator: IsolateEventGeneratorForAnnotation
// **************************************************************************

enum IsolateTestMessage { doOne }
enum EventOOOneMessage { doOne, doOneWtw }
enum EventTwoTMessage { doTwoTa, doTwoParT }

abstract class IsolateMeeResolveMain extends IsolateTest
    with Resolve, EventoneResolve, EventTwoResolve, EventTwoTResolve {
  @override
  bool resolve(resolveMessage) {
    if (remove(resolveMessage)) return true;
    if (resolveMessage is! IsolateSendMessage) return false;
    return super.resolve(resolveMessage);
  }
}

abstract class IsolateMeeMessagerMain extends IsolateTest
    with EventoneMessager, EventTwoMessager, EventTwoTMessager {}

mixin EventoneResolve on Resolve, Eventone, EventoneOne {
  late final _eventoneResolveFuncList =
      List<DynamicCallback>.unmodifiable([_doOne_0, _doOneWtw_1]);

  @override
  bool resolve(resolveMessage) {
    if (resolveMessage is IsolateSendMessage) {
      final type = resolveMessage.type;
      if (type is EventOOOneMessage) {
        dynamic result;
        try {
          result = _eventoneResolveFuncList
              .elementAt(type.index)(resolveMessage.args);
          receipt(result, resolveMessage);
        } catch (e) {
          receipt(result, resolveMessage, e);
        }
        return true;
      }
    }
    return super.resolve(resolveMessage);
  }

  Stream<String?> _doOne_0(args) => doOne();
  Future<String?> _doOneWtw_1(args) => doOneWtw();
}

/// implements [Eventone]
mixin EventoneMessager {
  SendEvent get sendEvent;

  Stream<String?> doOne() {
    return sendEvent.sendMessageStream(EventOOOneMessage.doOne, null);
  }

  Future<String?> doOneWtw() async {
    return sendEvent.sendMessage(EventOOOneMessage.doOneWtw, null);
  }
}

mixin EventTwoTResolve on Resolve, EventTwoT {
  late final _eventTwoTResolveFuncList =
      List<DynamicCallback>.unmodifiable([_doTwoTa_0, _doTwoParT_1]);

  @override
  bool resolve(resolveMessage) {
    if (resolveMessage is IsolateSendMessage) {
      final type = resolveMessage.type;
      if (type is EventTwoTMessage) {
        dynamic result;
        try {
          result = _eventTwoTResolveFuncList
              .elementAt(type.index)(resolveMessage.args);
          receipt(result, resolveMessage);
        } catch (e) {
          receipt(result, resolveMessage, e);
        }
        return true;
      }
    }
    return super.resolve(resolveMessage);
  }

  FutureOr<List<Map<int, String>>?> _doTwoTa_0(args) => doTwoTa();
  Future<String?> _doTwoParT_1(args) => doTwoParT(args);
}

/// implements [EventTwoT]
mixin EventTwoTMessager {
  SendEvent get sendEvent;

  FutureOr<List<Map<int, String>>?> doTwoTa() async {
    return sendEvent.sendMessage(EventTwoTMessage.doTwoTa, null);
  }

  Future<String?> doTwoParT(int a) async {
    return sendEvent.sendMessage(EventTwoTMessage.doTwoParT, a);
  }
}

mixin EventTwoResolve on Resolve, EventTwo {}

/// implements [EventTwo]
mixin EventTwoMessager {}
