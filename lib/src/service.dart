import 'dart:async';
import 'dart:math' show Random;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get_ip_address/get_ip_address.dart';

typedef RD = Map<String, dynamic>;
typedef OnGetReferrer = Future<RD> Function(String id);
typedef OnUpdateReferrer = Future<bool> Function(String id, RD);

class ReferralService {
  final String baseUrl;
  final String endPoint;
  final String queryField;
  final String referralsField;
  final String membersField;
  final String? appStoreId;
  final String? playStoreId;
  final OnGetReferrer onGetReferrer;
  final OnUpdateReferrer onUpdateReferrer;

  late final _x1 = FirebaseFirestore.instance.collection(referralsField);

  String? code;
  String? link;

  ReferralService._({
    required this.baseUrl,
    required this.endPoint,
    required this.queryField,
    required this.membersField,
    required this.referralsField,
    required this.appStoreId,
    required this.playStoreId,
    required this.onGetReferrer,
    required this.onUpdateReferrer,
  });

  static ReferralService? _i;

  static ReferralService init({
    bool resolveUrlStrategy = false,
    required String baseUrl,
    required OnGetReferrer onGetReferrer,
    required OnUpdateReferrer onUpdateReferrer,
    String endPoint = "referral",
    String queryField = "ref",
    String membersField = "members",
    String referralsField = "referrals",
    String? appStoreId,
    String? playStoreId,
  }) {
    return _i ??= ReferralService._(
      baseUrl: baseUrl,
      endPoint: endPoint,
      queryField: queryField,
      referralsField: referralsField,
      membersField: membersField,
      appStoreId: appStoreId,
      playStoreId: playStoreId,
      onGetReferrer: onGetReferrer,
      onUpdateReferrer: onUpdateReferrer,
    );
  }

  static ReferralService get i {
    if (_i != null) {
      return _i!;
    } else {
      throw UnimplementedError(
        "Please initialize ReferralService in main function",
      );
    }
  }

  /// LINK GENERATOR
  ///
  String _generateLink(String code) => "$baseUrl/$endPoint?$queryField=$code";

  String _generateCode({int length = 8}) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return String.fromCharCodes(
      List.generate(length, (index) {
        return chars.codeUnitAt(Random().nextInt(chars.length));
      }),
    );
  }

  Future<String> _generate(String uid, [bool linkMode = false]) async {
    return _fetch(uid).then((value) {
      final code = value?.referralCode ?? "";
      if (code.isNotEmpty) {
        if (linkMode) {
          final link = _generateLink(code);
          _i?.link = link;
          return link;
        } else {
          _i?.code = code;
          return code;
        }
      } else {
        final current = _generateCode();
        return _createReferral(id: current, uid: uid).then((_) {
          return _update(uid, {
            ReferrerKeys.i.referralCode: current,
          }).then((_) {
            if (linkMode) {
              final link = _generateLink(current);
              _i?.link = link;
              return link;
            } else {
              _i?.code = current;
              return current;
            }
          });
        });
      }
    });
  }

  Future<String> generateCode(String uid) => _generate(uid, false);

  Future<String> generateLink(String uid) => _generate(uid, true);

  Future<bool> _createReferral({
    String? id,
    String? uid,
    int plan = 1,
  }) {
    if (id == null || uid == null || id.isEmpty || uid.isEmpty || plan < 1) {
      return Future.value(false);
    }
    return _x1.doc(id).set({
      ReferralKeys.i.id: id,
      ReferralKeys.i.referrerId: uid,
      ReferralKeys.i.plan: plan,
    }).then((_) => true);
  }

  Future<bool> _updateReferral(String? id, Map<String, dynamic>? data) {
    if (id == null || data == null || id.isEmpty || data.isEmpty) {
      return Future.value(false);
    }
    return _x1.doc(id).update(data).then((_) => true);
  }

  Future<Referrer?> _fetch(String? uid) {
    if (uid == null || uid.isEmpty) return Future.value(null);
    return onGetReferrer.call(uid).then(Referrer.from);
  }

  Future<bool> _update(String? id, Map<String, dynamic>? data) {
    if (id == null || data == null || id.isEmpty || data.isEmpty) {
      return Future.value(false);
    }
    return onUpdateReferrer.call(id, data);
  }

  /// IP TAKER
  ///
  Future<String?> get _ip {
    return IpAddress().getIpAddress().then((v) => v is String ? v : null);
  }

  Future<bool> storeIp(String? code) async {
    if (code != null) {
      final ip = await _ip;
      if (ip != null && ip.isNotEmpty) {
        return _updateReferral(code, {
          ReferralKeys.i.ips: FieldValue.arrayUnion([ip]),
        });
      }
    }
    return true;
  }

  Future<bool> storeIpByPath(String path) async {
    final regex = RegExp('$queryField=([^&]+)');
    final match = regex.firstMatch(path);
    final code = match?.group(1);
    if (code != null && code.isNotEmpty) {
      await storeIp(code);
    }
    return true;
  }

  /// MEMBERSHIP
  ///
  Future<Referral?> getReferral(String id) async {
    return _x1.doc(id).get().then((value) {
      final data = value.data();
      if (data != null) {
        return Referral.from(data);
      } else {
        return null;
      }
    });
  }

  Future<Referral?> getReferralFromIp(String ip) async {
    return _x1.where(ReferralKeys.i.ips, arrayContains: ip).get().then((v) {
      if (v.docs.isNotEmpty) {
        final data = v.docs.firstOrNull?.data();
        if (data != null) {
          return Referral.from(data);
        } else {
          return null;
        }
      } else {
        return null;
      }
    });
  }

  Future<Referral?> getReferralFromUid(String uid) async {
    return _fetch(uid).then((value) {
      final code = value?.referralCode;
      if (code != null) {
        return getReferral(code);
      } else {
        return null;
      }
    });
  }

  Future<List<String>> getInstalls(String uid) {
    return getReferralFromUid(uid).then((value) => value?.installs ?? []);
  }

  Future<bool> isEligible(String? uid, {int? days}) {
    if (uid == null || uid.isEmpty) return Future.value(false);
    return _fetch(uid).then((user) {
      return isEligibleWith(
        createdAt: user?.rewardCreatedAt,
        days: days ?? user?.rewardDuration,
      );
    });
  }

  bool isEligibleWith({required int? createdAt, required int? days}) {
    if (createdAt != null && days != null && days > 0) {
      final creationDate = DateTime.fromMillisecondsSinceEpoch(createdAt);
      final currentDate = DateTime.now();
      final endDate = creationDate.add(Duration(days: days));
      return currentDate.isBefore(endDate);
    }
    return false;
  }

  Future<Referral?> _apply(Referrer user, [String? code]) async {
    final uid = user.id;
    final xInvalidUid = uid == null || uid.isEmpty;
    final xInvalidUser = xInvalidUid || user.isRedeemed;
    if (xInvalidUser) return Future.value(null);
    final xCM = code != null && code.isNotEmpty;
    final ip = xCM ? null : await _ip;
    final r = await (xCM ? getReferral(code) : getReferralFromIp(ip ?? ""));
    final isInvalidCode = r == null || (r.id ?? "").isEmpty;
    final isInvalidUid = user.isReferral(r?.id);
    if (!isInvalidCode && !isInvalidUid) {
      return _update(uid, {
        ReferrerKeys.i.redeemed: true,
        ReferrerKeys.i.rewardDuration: Rewards.x1.duration,
        ReferrerKeys.i.rewardTokens: Rewards.x1.tokens,
        ReferrerKeys.i.rewardCreatedAt: Rewards.x1.createdAt,
      })
          .then((_) {
            return _fetch(r.referrerId)
                .then((referrer) {
                  if (referrer == null) return Future.value(true);
                  final installs = (r.installs?.length ?? 0) + 1;
                  final reward = Rewards.from(installs, referrer.reward ?? 0);
                  if (reward.isX1 || reward.isX2 || reward.isX3) {
                    return _update(r.referrerId, {
                      ReferrerKeys.i.reward: reward.category,
                      ReferrerKeys.i.rewardDuration: reward.duration,
                      ReferrerKeys.i.rewardTokens: reward.tokens,
                      ReferrerKeys.i.rewardCreatedAt: reward.createdAt,
                    })
                        .then((_) {
                          return _updateReferral(r.id, {
                            if (!xCM)
                              ReferralKeys.i.ips: FieldValue.arrayRemove([ip]),
                            ReferralKeys.i.installs:
                                FieldValue.arrayUnion([uid]),
                          }).onError((_, __) => true).then((_) => true);
                        })
                        .onError((_, __) => true)
                        .then((_) => true);
                  } else {
                    return _updateReferral(r.id, {
                      if (!xCM)
                        ReferralKeys.i.ips: FieldValue.arrayRemove([ip]),
                      ReferralKeys.i.installs: FieldValue.arrayUnion([uid]),
                    }).onError((_, __) => true).then((_) => true);
                  }
                })
                .onError((_, __) => true)
                .then((_) => true);
          })
          .onError((_, __) => false)
          .then((_) => r);
    } else {
      return null;
    }
  }

  Future<Referral?> redeem(String? uid, [String? code]) {
    if (uid == null || uid.isEmpty) return Future.value(null);
    return _fetch(uid).then((user) {
      if (user != null) {
        return _apply(user, code);
      }
      return null;
    });
  }

  int tokens = 0;

  Future<int> getTokens(String? uid) {
    if (uid == null || uid.isEmpty) return Future.value(0);
    return _fetch(uid).then((user) {
      if (user != null) {
        final tokens = user.rewardTokens ?? 0;
        _i?.tokens = tokens;
        return tokens;
      }
      return 0;
    });
  }

  Future<int> tokenIncrement(String uid, int value) async {
    if (uid.isNotEmpty) {
      return onUpdateReferrer.call(uid, {
        ReferrerKeys.i.rewardTokens: FieldValue.increment(value),
      }).then((_) {
        if (_) {
          return getTokens(uid);
        } else {
          return tokens;
        }
      });
    } else {
      return tokens;
    }
  }
}

enum Rewards {
  x1(category: 1, duration: 0, tokens: 0),
  x2(category: 2, duration: 0, tokens: 1),
  x3(category: 3, duration: 0, tokens: 0),
  none(category: 0, duration: 0, tokens: 0);

  final int category;
  final int duration;
  final int tokens;

  const Rewards({
    required this.category,
    required this.duration,
    required this.tokens,
  });

  bool get isX1 => this == x1;

  bool get isX2 => this == x2;

  bool get isX3 => this == x3;

  bool get isNone => this == none;

  factory Rewards.from(int installs, int previousPlan) {
    if (installs == 1 && previousPlan == 0) {
      return Rewards.x1;
    } else if (installs == 3 && previousPlan == 1) {
      return Rewards.x2;
      // } else if (installs == 12 && previousPlan == 2) {
      //   return Rewards.x3;
    } else {
      return Rewards.none;
    }
  }

  int get createdAt => DateTime.now().millisecondsSinceEpoch;

  int get expireAt {
    final now = DateTime.now();
    if (isX1) {
      return now.add(Duration(days: x1.duration)).millisecondsSinceEpoch;
    } else if (isX2) {
      return now.add(Duration(days: x2.duration)).millisecondsSinceEpoch;
    } else if (isX3) {
      return now.add(Duration(days: x3.duration)).millisecondsSinceEpoch;
    } else {
      return now.millisecondsSinceEpoch;
    }
  }
}

class ReferralKeys {
  final id = "id";
  final referrerId = "referrer_id";
  final plan = "plan";
  final ips = "ips";
  final installs = "installs";
  final members = "members";

  const ReferralKeys._();

  static ReferralKeys? _i;

  static ReferralKeys get i => _i ??= const ReferralKeys._();
}

class Referral {
  final String? id;
  final String? referrerId;
  final int? plan;
  final List<String>? installs;
  final List<String>? ips;
  final List<String>? members;

  const Referral({
    this.id,
    this.referrerId,
    this.plan,
    this.installs,
    this.ips,
    this.members,
  });

  bool isIp(String? ip) => (ips ?? []).contains(ip);

  bool isMember(String? uid) => (members ?? []).contains(uid);

  factory Referral.from(Map<String, dynamic> source) {
    final id = source[ReferralKeys.i.id];
    final uid = source[ReferralKeys.i.referrerId];
    final plan = source[ReferralKeys.i.plan];
    final installs = source[ReferralKeys.i.installs];
    final ips = source[ReferralKeys.i.ips];
    final members = source[ReferralKeys.i.members];
    return Referral(
      id: id is String ? id : null,
      referrerId: uid is String ? uid : null,
      plan: plan is int ? plan : null,
      installs: installs is List ? installs.map((e) => "$e").toList() : null,
      ips: ips is List ? ips.map((e) => "$e").toList() : null,
      members: members is List ? members.map((e) => "$e").toList() : null,
    );
  }
}

class ReferrerKeys {
  final id = "id";
  final redeemed = "redeemed";
  final redeemedCode = "redeemed_code";
  final referralCode = "referral_code";
  final referralExpired = "referral_expired";
  final reward = "reward";
  final rewardDuration = "reward_duration";
  final rewardTokens = "reward_tokens";
  final rewardCreatedAt = "reward_created_at";
  final rewardExpireAt = "reward_expire_at";

  const ReferrerKeys._();

  static ReferrerKeys? _i;

  static ReferrerKeys get i => _i ??= const ReferrerKeys._();
}

class Referrer {
  final String? id;
  final bool? redeemed;
  final String? redeemedCode;
  final String? referralCode;
  final bool? referralExpired;
  final int? reward;
  final int? rewardDuration;
  final int? rewardCreatedAt;
  final int? rewardExpireAt;
  final int? rewardTokens;

  String get noneUid {
    return id ?? DateTime.timestamp().millisecondsSinceEpoch.toString();
  }

  bool get isCurrentUid => id == "1706388765933";

  bool get isEligible {
    return ReferralService.i.isEligibleWith(
      createdAt: rewardCreatedAt,
      days: rewardDuration,
    );
  }

  bool get isRedeemed => redeemed ?? false;

  bool get isReferralExpired => referralExpired ?? false;

  const Referrer({
    this.id,
    this.redeemed,
    this.redeemedCode,
    this.referralCode,
    this.referralExpired,
    this.reward,
    this.rewardDuration,
    this.rewardCreatedAt,
    this.rewardExpireAt,
    this.rewardTokens,
  });

  bool isReferral(String? code) => referralCode == code;

  factory Referrer.from(Map<String, dynamic> source) {
    final id = source[ReferrerKeys.i.id];
    final redeemed = source[ReferrerKeys.i.redeemed];
    final redeemedCode = source[ReferrerKeys.i.redeemedCode];
    final referralCode = source[ReferrerKeys.i.referralCode];
    final referralExpired = source[ReferrerKeys.i.referralExpired];
    final reward = source[ReferrerKeys.i.reward];
    final rewardDuration = source[ReferrerKeys.i.rewardDuration];
    final rewardCreatedAt = source[ReferrerKeys.i.rewardCreatedAt];
    final rewardExpireAt = source[ReferrerKeys.i.rewardExpireAt];
    final rewardTokens = source[ReferrerKeys.i.rewardTokens];
    return Referrer(
      id: id is String ? id : null,
      redeemed: redeemed is bool ? redeemed : null,
      redeemedCode: redeemedCode is String ? redeemedCode : null,
      referralCode: referralCode is String ? referralCode : null,
      referralExpired: referralExpired is bool ? referralExpired : null,
      reward: reward is int ? reward : null,
      rewardDuration: rewardDuration is int ? rewardDuration : null,
      rewardCreatedAt: rewardCreatedAt is int ? rewardCreatedAt : null,
      rewardExpireAt: rewardExpireAt is int ? rewardExpireAt : null,
      rewardTokens: rewardTokens is int ? rewardTokens : null,
    );
  }

  Referrer copy({
    String? id,
    bool? redeemed,
    String? redeemedCode,
    bool redeemClear = false,
    String? referralCode,
    bool? referralExpired,
    int? reward,
    int? rewardDuration,
    int? rewardCreatedAt,
    int? rewardExpireAt,
    int? rewardTokens,
  }) {
    return Referrer(
      id: id ?? this.id,
      redeemed: redeemed ?? this.redeemed,
      referralCode: referralCode ?? this.referralCode,
      redeemedCode: redeemClear ? null : redeemedCode ?? this.redeemedCode,
      referralExpired: referralExpired ?? this.referralExpired,
      reward: reward ?? this.reward,
      rewardDuration: rewardDuration ?? this.rewardDuration,
      rewardCreatedAt: rewardCreatedAt ?? this.rewardCreatedAt,
      rewardExpireAt: rewardExpireAt ?? this.rewardExpireAt,
      rewardTokens: rewardTokens ?? this.rewardTokens,
    );
  }

  Map<String, dynamic> get source {
    return {
      ReferrerKeys.i.id: id,
      ReferrerKeys.i.redeemed: redeemed,
      ReferrerKeys.i.redeemedCode: redeemedCode,
      ReferrerKeys.i.referralCode: referralCode,
      ReferrerKeys.i.referralExpired: referralExpired,
      ReferrerKeys.i.reward: reward,
      ReferrerKeys.i.rewardDuration: rewardDuration,
      ReferrerKeys.i.rewardCreatedAt: rewardCreatedAt,
      ReferrerKeys.i.rewardExpireAt: rewardExpireAt,
      ReferrerKeys.i.rewardTokens: rewardTokens,
    };
  }
}
