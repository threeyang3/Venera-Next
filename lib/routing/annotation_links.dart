import 'package:venera_next/features/annotations/presentation/annotation_services_scope.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/components/message.dart';
import 'package:venera_next/foundation/annotation_link_contract.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/navigation_admission.dart';
import 'app_navigation.dart';
import 'local_reading.dart';

Future<bool> handleAnnotationAppLink(
  Uri uri, {
  bool Function()? isActive,
}) async {
  bool active() {
    final context = appNavigation.rootNavigatorKey.currentContext;
    return isActive?.call() != false &&
        context != null &&
        NavigationAdmission.allows(context);
  }

  if (!active()) return false;
  try {
    if (!const bool.fromEnvironment('COMICNOTES_POC')) {
      throw StateError('请启用批注工作模式后打开此链接');
    }
    final link = AnnotationLink.parse(uri);
    if (link == null) throw const FormatException('无效的漫画批注链接');
    final rootContext = appNavigation.rootNavigatorKey.currentContext!;
    final resolve = AnnotationServicesScope.maybeOf(rootContext)?.resolveLink;
    if (resolve == null) throw StateError('批注定位服务尚未就绪');
    final target = await resolve(link);
    if (!active()) return false;
    final comic = LocalManager().find(target.comicId, ComicType.local);
    if (comic == null ||
        comic.createdAt.millisecondsSinceEpoch !=
            target.createdAtMilliseconds ||
        target.annotationId != link.annotationId ||
        target.chapter < 1 ||
        target.imageNumber < 1) {
      throw StateError('漫画或批注目标在定位过程中发生变化，请重试');
    }
    openLocalComic(
      comic,
      chapter: target.chapter,
      imageNumber: target.imageNumber,
      annotationId: target.annotationId,
    );
    return true;
  } catch (error, stack) {
    Log.error('Annotation link', error, stack);
    final context = appNavigation.rootNavigatorKey.currentContext;
    if (active() && context != null && context.mounted) {
      showToast(message: '无法打开批注：$error', context: context);
    }
    return false;
  }
}
