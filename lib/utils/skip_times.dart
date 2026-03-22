import 'package:nyantv/utils/aniskip.dart' as aniskip;
import 'package:nyantv/utils/introdb.dart' as introdb;

class EpisodeSkipTimes {
  final SkipIntervals? op;
  final SkipIntervals? ed;
  final SkipIntervals? recap;
  final SkipIntervals? mixedOp;
  final SkipIntervals? mixedEd;

  EpisodeSkipTimes({this.op, this.ed, this.recap, this.mixedOp, this.mixedEd});

  factory EpisodeSkipTimes.fromAniSkip(aniskip.EpisodeSkipTimes s) =>
      EpisodeSkipTimes(
        op: s.op != null
            ? SkipIntervals(start: s.op!.start, end: s.op!.end)
            : null,
        ed: s.ed != null
            ? SkipIntervals(start: s.ed!.start, end: s.ed!.end)
            : null,
        recap: s.recap != null
            ? SkipIntervals(start: s.recap!.start, end: s.recap!.end)
            : null,
        mixedOp: s.mixedOp != null
            ? SkipIntervals(start: s.mixedOp!.start, end: s.mixedOp!.end)
            : null,
        mixedEd: s.mixedEd != null
            ? SkipIntervals(start: s.mixedEd!.start, end: s.mixedEd!.end)
            : null,
      );

  factory EpisodeSkipTimes.fromIntroDb(introdb.EpisodeSkipTimes s) =>
      EpisodeSkipTimes(
        op: s.op != null
            ? SkipIntervals(start: s.op!.start, end: s.op!.end)
            : null,
        ed: s.ed != null
            ? SkipIntervals(start: s.ed!.start, end: s.ed!.end)
            : null,
        recap: s.recap != null
            ? SkipIntervals(start: s.recap!.start, end: s.recap!.end)
            : null,
      );
}

class SkipIntervals {
  final int start;
  final int end;
  SkipIntervals({required this.start, required this.end});
}
