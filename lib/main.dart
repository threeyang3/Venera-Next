import 'package:venera_next/app_runtime/annotation_manual_recovery.dart';
import 'package:venera_next/app_shell/import_commands.dart';
import 'package:venera_next/features/local_comics/local_comics.dart'
    show showLocalComicImportDialog;
import 'package:venera_next/foundation/navigation_admission.dart';
import 'package:venera_next/features/history/image_favorites.dart';
import 'package:venera_next/app_runtime/annotations.dart';
import 'package:venera_next/app_runtime/annotation_export_binding.dart';
import 'package:venera_next/app_runtime/annotation_navigation.dart';
import 'package:venera_next/features/annotations/presentation/annotation_services_scope.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/history/history_scope.dart';
import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'package:venera_next/features/history/history_manager.dart';
import 'package:venera_next/app_runtime/data_sync.dart';
import 'package:venera_next/app_runtime/bootstrap_core.dart';
import 'package:venera_next/app_runtime/core_bootstrap.dart';
import 'package:venera_next/app_runtime/application_host.dart';
import 'package:venera_next/app_runtime/application_updates.dart';
import 'package:venera_next/components/application_update_prompt.dart';
import 'package:venera_next/app_runtime/image_loading.dart';
import 'package:venera_next/app_runtime/follow_updates.dart';
import 'package:venera_next/app_runtime/webdav_library.dart';
import 'package:venera_next/features/reader/reader.dart'
    show ReaderPlatformEffectsScope, ReaderSessionScope;
import 'package:venera_next/features/follow_updates/follow_updates.dart';
import 'package:venera_next/app_runtime/background_sync.dart';
import 'package:venera_next/app_runtime/interactive_platform_bindings.dart';
import 'package:venera_next/app_runtime/window_placement.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'dart:async';
import 'package:venera_next/app_runtime/sync_window_binding.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';
import 'app_runtime/annotation_source_relocation.dart';
import 'app_runtime/annotation_recovery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:venera_next/app_runtime/app_runtime.dart';
import 'package:venera_next/app_shell/app_shell.dart';
import 'package:venera_next/app_shell/startup_failure.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/file_interaction.dart';
import 'components/gesture.dart';
import 'components/js_ui.dart';
import 'components/message.dart';
import 'components/window_frame.dart';
import 'components/window_selection_task.dart';
import 'foundation/app.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'foundation/app_locale.dart';
import 'foundation/appdata.dart';
import 'foundation/context.dart';
import 'foundation/js_engine.dart';
import 'features/webdav_library/webdav_library.dart';
import 'features/sync/sync.dart';
import 'features/comic_source/comic_source_api.dart';
import 'features/comic_source/comic_source_ui.dart';
import 'features/comic_source/source_repositories.dart';
import 'network/app_dio.dart';

void main(List<String> args) {
  if (args.contains('--headless')) {
    runHeadlessMode(args);
    return;
  }
  if (runWebViewTitleBarWidget(args)) return;
  var applicationShown = false;
  Future<void> showFailure(Object error, StackTrace stack) async {
    if (applicationShown) return;
    applicationShown = true;
    runApp(StartupFailureApp(error: error, stack: stack));
    if (App.isDesktop) {
      try {
        await showStartupFailureWindow();
      } catch (windowError, windowStack) {
        Log.error('Startup window', windowError, windowStack);
      }
    }
  }

  overrideIO(() {
    runZonedGuarded(
      () async {
        try {
          WidgetsFlutterBinding.ensureInitialized();
          registerShowMessageHandler((context, message) {
            showToast(message: message, context: context);
          });
          JsEngine().bindUiMessageHandler(JsUiApi());
          final sync = createApplicationDataSync();
          final core = createCoreBootstrap(
            onDataChanged: sync.onDataChanged,
            // Rollback still joins live JS callbacks and retains storage
            // ownership. Its completion must not gate the first error frame.
            onStartupFailure: (_, error, stack) =>
                unawaited(showFailure(error, stack)),
          );
          try {
            await init(core);
          } catch (error, stack) {
            await rollbackCoreStartup(
              [
                (name: 'sync', close: sync.closeAndWait),
                (name: 'core', close: core.close),
              ],
              error,
              stack,
            );
            Error.throwWithStackTrace(error, stack);
          }
          final placement = App.isDesktop
              ? WindowPlacementHost.platform(
                  dataPath: App.dataPath,
                  linux: App.isLinux,
                  macos: App.isMacOS,
                )
              : null;
          final host = ApplicationHost(
            core: core,
            sync: sync,
            placement: placement,
            sourceInstallations: SourceInstallations(
              manager: ComicSourceManager(),
              repositories: SourceRepositories.instance,
              createClient: AppDio.new,
            ),
          );
          runApp(MyApp(host: host));
          applicationShown = true;
          await placement?.initialize();
        } catch (error, stack) {
          Log.error('Startup', error, stack);
          await showFailure(error, stack);
        }
      },
      (error, stack) {
        Log.error("Unhandled Exception", error, stack);
      },
    );
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.host});

  /// The host owns this controller beyond an individual widget mount.
  final ApplicationHost host;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _importCommandRoutes = ImportCommandRoutes();
  bool _hasAuthenticated = false;
  bool get _comicNotesCommands =>
      App.isMacOS &&
      const bool.fromEnvironment('COMICNOTES_POC') &&
      const bool.fromEnvironment('COMICNOTES_WORKSPACE');
  late final _library = webDavLibrary;
  late final _interactiveBindings = createPlatformInteractiveBindings(
    placement: widget.host.placement?.attach(),
  );
  late final _dataSync = widget.host.sync;
  ApplicationMount? _mount;
  late final _followUpdates = createFollowUpdatesRuntime(_dataSync);
  late final _backgroundSync = BackgroundSync.platform(_dataSync);
  late final _startupUpdates = createStartupUpdateCheck(
    sources: widget.host.sourceUpdates,
    checkApplication: (scope) async {
      if (!mounted || widget.host.isClosing) return;
      final navigator = appNavigation.rootNavigatorKey.currentState;
      final context = navigator?.overlay?.context;
      if (context == null || !context.mounted) return;
      await ApplicationUpdatePrompt(
        context: context,
        service: widget.host.applicationUpdates,
        parent: scope,
        isActive: () => mounted && !widget.host.isClosing,
      ).check(silent: true, delay: const Duration(seconds: 2));
    },
  );

  @override
  void initState() {
    super.initState();
    if (widget.host.isClosing) return;
    _mount = widget.host.attach(
      stop: () {
        _backgroundSync.stop();
        _startupUpdates.cancel();
      },
      close: () => closeApplicationMountBindings(
        followUpdates: _followUpdates,
        interactive: _interactiveBindings,
        closeStartupUpdates: _startupUpdates.closeAndWait,
      ),
    );
    mountWebDavLibrary(_library);
    appNavigation.registerForceRebuild(forceRebuild);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.host.isClosing) {
        _interactiveBindings.start();
        _backgroundSync.start();
        _followUpdates.start();
        unawaited(
          _startupUpdates.start().catchError((Object error, StackTrace stack) {
            Log.error('Startup update check', error, stack);
          }),
        );
      }
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (_mount == null) {
      super.dispose();
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    appNavigation.registerForceRebuild(null);
    hideContentOverlay?.remove();
    hideContentOverlay = null;
    unawaited(
      _mount!.closeAndWait().catchError((Object error, StackTrace stack) {
        Log.error('Interactive bindings', error, stack);
      }),
    );
    super.dispose();
  }

  bool isAuthPageActive = false;

  OverlayEntry? hideContentOverlay;

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (mounted &&
        GlobalPreferenceStore(appdata.settings).read(AppPreferences.language) ==
            'system') {
      forceRebuild();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.host.isClosing) return;
    if (state == AppLifecycleState.resumed) {
      _dataSync.checkForAutomaticSync();
      _library.source.synchronizer.checkForAutomaticSync();
    }
    if (!App.isMobile ||
        !GlobalPreferenceStore(
          appdata.settings,
        ).read(AppPreferences.authorizationRequired)) {
      return;
    }
    if (state == AppLifecycleState.inactive && hideContentOverlay == null) {
      hideContentOverlay = OverlayEntry(
        builder: (context) {
          return Positioned.fill(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: appNavigation.rootContext.colorScheme.surface,
            ),
          );
        },
      );
      Overlay.of(appNavigation.rootContext).insert(hideContentOverlay!);
    } else if (hideContentOverlay != null &&
        state == AppLifecycleState.resumed) {
      hideContentOverlay!.remove();
      hideContentOverlay = null;
    }
    if (state == AppLifecycleState.hidden &&
        !isAuthPageActive &&
        !IO.isSelectingFiles) {
      isAuthPageActive = true;
      appNavigation.rootContext.to(
        () => AuthPage(
          onSuccessfulAuth: () {
            appNavigation.rootContext.pop();
            isAuthPageActive = false;
          },
        ),
      );
    }
    super.didChangeAppLifecycleState(state);
  }

  void forceRebuild() {
    if (!mounted || widget.host.isClosing) return;
    void rebuild(Element el) {
      el.markNeedsBuild();
      el.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
    setState(() {});
  }

  Color translateColorSetting() {
    return switch (GlobalPreferenceStore(appdata.settings).appearance.color) {
      'red' => Colors.red,
      'pink' => Colors.pink,
      'purple' => Colors.purple,
      'green' => Colors.green,
      'orange' => Colors.orange,
      'blue' => Colors.blue,
      'yellow' => Colors.yellow,
      'cyan' => Colors.cyan,
      _ => Colors.blue,
    };
  }

  ThemeData getTheme(
    Color primary,
    Color? secondary,
    Color? tertiary,
    Brightness brightness,
  ) {
    if (App.isMacOS && const bool.fromEnvironment('COMICNOTES_WORKSPACE')) {
      final dark = brightness == Brightness.dark;
      final surface = dark ? const Color(0xff202020) : Colors.white;
      final chrome = dark ? const Color(0xff2b2b2b) : const Color(0xfff3f3f3);
      final ink = dark ? const Color(0xffeeeeee) : const Color(0xff242424);
      final blue = dark ? const Color(0xff0a84ff) : const Color(0xff007aff);
      final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
      );
      return ThemeData(
        brightness: brightness,
        platform: TargetPlatform.macOS,
        fontFamily: '.AppleSystemUIFont',
        fontFamilyFallback: const [
          'PingFang SC',
          'Hiragino Sans',
          'sans-serif',
        ],
        visualDensity: VisualDensity.compact,
        splashFactory: NoSplash.splashFactory,
        scaffoldBackgroundColor: surface,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: blue,
              brightness: brightness,
            ).copyWith(
              primary: blue,
              surface: surface,
              onSurface: ink,
              surfaceTint: Colors.transparent,
              surfaceContainerLow: chrome,
              surfaceContainer: chrome,
              surfaceContainerHigh: chrome,
              surfaceContainerHighest: chrome,
              outline: dark ? const Color(0xff555555) : const Color(0xffc7c7c7),
              outlineVariant: dark
                  ? const Color(0xff3d3d3d)
                  : const Color(0xffdedede),
            ),
        textTheme: Typography.material2021().black
            .apply(
              fontFamily: '.AppleSystemUIFont',
              bodyColor: ink,
              displayColor: ink,
            )
            .copyWith(
              bodyMedium: TextStyle(fontSize: 13, color: ink, height: 1.4),
              bodySmall: TextStyle(
                fontSize: 11,
                color: ink.withValues(alpha: .65),
              ),
              titleLarge: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
              titleMedium: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
              labelLarge: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: ink,
              ),
            ),
        iconTheme: IconThemeData(size: 18, color: ink.withValues(alpha: .75)),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: ink.withValues(alpha: .75),
            minimumSize: const Size(30, 28),
            padding: const EdgeInsets.all(5),
            shape: shape,
            iconSize: 18,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: blue,
            foregroundColor: Colors.white,
            minimumSize: const Size(64, 28),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: shape,
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 28),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: shape,
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 28),
            shape: shape,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: chrome,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          titleTextStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 9,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(
              color: dark ? const Color(0xff505050) : const Color(0xffc7c7c7),
              width: .7,
            ),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: dark ? const Color(0xff414141) : const Color(0xffdedede),
          thickness: .5,
        ),
        scrollbarTheme: const ScrollbarThemeData(
          thickness: WidgetStatePropertyAll(5),
          radius: Radius.circular(3),
        ),
      );
    }
    String? font;
    List<String>? fallback;
    if (App.isLinux || App.isWindows) {
      font = 'Noto Sans CJK';
      fallback = [
        'Segoe UI',
        'Noto Sans SC',
        'Noto Sans TC',
        'Noto Sans',
        'Microsoft YaHei',
        'PingFang SC',
        'Arial',
        'sans-serif',
      ];
    }
    return ThemeData(
      colorScheme: SeedColorScheme.fromSeeds(
        primaryKey: primary,
        secondaryKey: secondary,
        tertiaryKey: tertiary,
        brightness: brightness,
        tones: FlexTones.vividBackground(brightness),
      ),
      fontFamily: font,
      fontFamilyFallback: fallback,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
      ),
      listTileTheme: ListTileThemeData(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_mount == null) {
      return MaterialApp(
        builder: (_, child) => WindowFrame(
          child!,
          isFinalizing: () => widget.host.isClosing,
          finalize: (drain) => widget.host.close(drain: drain),
        ),
        home: const SizedBox.expand(),
      );
    }
    Widget home;
    if (GlobalPreferenceStore(
      appdata.settings,
    ).read(AppPreferences.authorizationRequired)) {
      home = AuthPage(
        onSuccessfulAuth: () {
          _hasAuthenticated = true;
          appNavigation.rootContext.toReplacement(() => const MainPage());
        },
      );
    } else {
      home = const MainPage();
    }
    return DynamicColorBuilder(
      builder: (light, dark) {
        Color? primary, secondary, tertiary;
        if (GlobalPreferenceStore(appdata.settings).appearance.color !=
                'system' ||
            light == null ||
            dark == null) {
          primary = translateColorSetting();
        } else {
          primary = light.primary;
          secondary = light.secondary;
          tertiary = light.tertiary;
        }
        return MaterialApp(
          title: "VeneraNext",
          home: home,
          debugShowCheckedModeBanner: false,
          theme: getTheme(primary, secondary, tertiary, Brightness.light),
          navigatorKey: appNavigation.rootNavigatorKey,
          navigatorObservers: [if (_comicNotesCommands) _importCommandRoutes],
          darkTheme: getTheme(primary, secondary, tertiary, Brightness.dark),
          themeMode: switch (GlobalPreferenceStore(
            appdata.settings,
          ).appearance.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          color: Colors.transparent,
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          locale: appLocale,
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('zh', 'TW'),
            Locale('en'),
          ],
          builder: (context, widget) {
            ErrorWidget.builder = (details) {
              Log.error(
                "Unhandled Exception",
                "${details.exception}\n${details.stack}",
              );
              return Material(
                child: Center(child: Text(details.exception.toString())),
              );
            };
            if (widget != null) {
              /// 如果无法检测到状态栏高度设定指定高度
              /// https://github.com/flutter/flutter/issues/161086
              var isPaddingCheckError =
                  MediaQuery.of(context).viewPadding.top <= 0 ||
                  MediaQuery.of(context).viewPadding.top > 200;

              if (isPaddingCheckError && Platform.isAndroid) {
                widget = MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    viewPadding: const EdgeInsets.only(top: 15, bottom: 15),
                    padding: const EdgeInsets.only(top: 15, bottom: 15),
                  ),
                  child: widget,
                );
              }

              widget = FavoritesScope(
                manager: LocalFavoritesManager(),
                child: HistoryScope(
                  manager: HistoryManager(),
                  imageFavorites: ImageFavoriteManager(),
                  child: widget,
                ),
              );
              if (_comicNotesCommands) {
                widget = ImportCommands(
                  routes: _importCommandRoutes,
                  canOpen: () =>
                      mounted &&
                      !this.widget.host.isClosing &&
                      (!GlobalPreferenceStore(
                            appdata.settings,
                          ).read(AppPreferences.authorizationRequired) ||
                          _hasAuthenticated) &&
                      appNavigation.rootNavigatorKey.currentContext != null &&
                      NavigationAdmission.allows(appNavigation.rootContext),
                  open: () =>
                      showLocalComicImportDialog(appNavigation.rootContext),
                  child: widget,
                );
              }
              widget = ReaderPlatformEffectsScope(child: OverlayWidget(widget));
              if (App.isDesktop) {
                widget = WindowFrame(
                  Shortcuts(
                    shortcuts: {
                      LogicalKeySet(LogicalKeyboardKey.escape):
                          VoidCallbackIntent(appNavigation.pop),
                    },
                    child: MouseBackDetector(
                      onTapDown: appNavigation.pop,
                      child: SyncWindowBinding(
                        controller: _dataSync,
                        waitForHistoryWrites:
                            HistoryManager().waitForAsyncWrites,
                        isFinalizing: () => this.widget.host.isClosing,
                        prepareInteractive: _interactiveBindings.prepareForExit,
                        prepareFollowUpdates: () =>
                            prepareApplicationFollowUpdatesForExit(
                              _followUpdates,
                            ),
                        prepareWebDavLibrary: _library.source.prepareForExit,
                        prepareImages: prepareImageLoadingForExit,
                        cancelStartupUpdates: _startupUpdates.cancel,
                        closeStartupUpdates: _startupUpdates.closeAndWait,
                        child: widget,
                      ),
                    ),
                  ),
                  debugAction: reloadComicSourcesForDebug,
                  finalize: (drain) => this.widget.host.close(drain: drain),
                  isFinalizing: () => this.widget.host.isClosing,
                );
              }
              widget = FollowUpdatesScope(
                runtime: _followUpdates,
                child: widget,
              );
              widget = SelectionTasksScope(
                registry: this.widget.host.selections,
                child: widget,
              );
              widget = ReaderSessionScope(
                onClosed: _dataSync.onDataChanged,
                child: widget,
              );
              widget = AnnotationServicesScope(
                openSession: openLocalAnnotationSession,
                exportNotes: exportLocalAnnotations,
                backupNotes: backupLocalAnnotations,
                prepareRestore: prepareLocalAnnotationRestore,
                relocateOriginal: selectAnnotationOriginal,
                findRecovery: findRecoverableAnnotations,
                recoverNotes: recoverLocalAnnotations,
                findManualRecovery: findManualAnnotationRecovery,
                prepareManualRecovery: prepareManualAnnotationRecovery,
                locatePage: locateRegisteredAnnotationPage,
                resolveLink: resolveAnnotationLinkDestination,
                child: widget,
              );
              widget = DataSyncScope(controller: _dataSync, child: widget);
              widget = ApplicationUpdateScope(
                service: this.widget.host.applicationUpdates,
                child: widget,
              );
              widget = WebDavLibraryScope(services: _library, child: widget);
              final installations = this.widget.host.sourceInstallations;
              if (installations != null) {
                widget = SourceInstallationsScope(
                  queue: installations,
                  updates: this.widget.host.sourceUpdates,
                  refresh: forceRebuild,
                  child: widget,
                );
              }
              return _SystemUiProvider(
                Material(
                  color: App.isLinux ? Colors.transparent : null,
                  child: widget,
                ),
              );
            }
            throw ('widget is null');
          },
        );
      },
    );
  }
}

class _SystemUiProvider extends StatelessWidget {
  const _SystemUiProvider(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    var brightness = Theme.of(context).brightness;
    SystemUiOverlayStyle systemUiStyle;
    if (brightness == Brightness.light) {
      systemUiStyle = SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      );
    } else {
      systemUiStyle = SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiStyle,
      child: child,
    );
  }
}
