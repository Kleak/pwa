import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_style/dart_style.dart';
import 'package:glob/glob.dart';
import 'package:yaml/yaml.dart' as yaml;

Future main(List<String> args) async {
  ArgResults argv = (new ArgParser()
        ..addOption('offline', allowMultiple: true, defaultsTo: 'build/web')
        ..addOption('index-html', defaultsTo: 'index.html')
        ..addOption('exclude', allowMultiple: true)
        ..addOption('exclude-defaults', defaultsTo: 'true')
        ..addOption('lib-dir', defaultsTo: 'lib/pwa')
        ..addOption('lib-include')
        ..addOption('web-dir', defaultsTo: 'web'))
      .parse(args);

  List<String> offlineDirs = argv['offline'];
  await buildProjectIfEmpty(offlineDirs);
  List<String> offlineUrls = await scanOfflineUrls(offlineDirs, argv);
  String offlineUrlsFile = '${argv['lib-dir']}/offline_urls.g.dart';
  await writeOfflineUrls(offlineUrls, offlineUrlsFile);

  String libInclude = await detectLibInclude(argv);
  if (libInclude == null) {
    print('Unable to detect library include prefix. '
        'Run script from the root of the project or specify lib-include.');
    exit(-1);
  }
  await generateWorkerScript(argv, libInclude);
}

/// If build/web is empty, run `pub build`.
Future buildProjectIfEmpty(List<String> offlineDirs) async {
  // This works only with the default value.
  if (offlineDirs.length == 1 && offlineDirs.first == 'build/web') {
    Directory dir = new Directory('build/web');
    if (dir.existsSync() && dir.listSync().isNotEmpty) return;
    print('Running pub build the first time:');
    String executable = Platform.isWindows ? 'pub.exe' : 'pub';
    print('$executable build');
    print('-----');
    Process process = await Process.start(executable, ['build']);
    Future f1 = stdout.addStream(process.stdout);
    Future f2 = stderr.addStream(process.stderr);
    await Future.wait([f1, f2]);
    int exitCode = await process.exitCode;
    print('-----');
    String status = exitCode == 0 ? 'OK' : 'Some error happened.';
    print('Pub build exited with code $exitCode ($status).');
  }
}

/// Scans all of the directories and returns the URLs derived from the files.
Future<List<String>> scanOfflineUrls(
    List<String> offlineDirs, ArgResults argv) async {
  String indexHtml = argv['index-html'];
  List<String> excludes = argv['exclude'];
  bool excludeDefaults = argv['exclude-defaults'] == 'true';

  List<Glob> excludeGlobs = [];
  if (excludeDefaults) {
    excludeGlobs.addAll([
      // Dart Analyzer
      '**/format.fbs',
      // Angular
      '**.ng_meta.json',
      '**.ng_summary.json',
      '**/README.txt',
      '**/README.md',
      '**/LICENSE',
      // PWA
      'pwa.dart.js',
      'pwa.g.dart.js',
    ].map((s) => new Glob(s)));
  }
  excludeGlobs.addAll(excludes.map((s) => new Glob(s)));

  Set<String> urls = new Set();
  for (String dirName in offlineDirs) {
    Directory dir = new Directory(dirName);
    var list = await dir.list(recursive: true).toList();
    for (FileSystemEntity fse in list) {
      if (fse is! File) continue;
      String name = fse.path.substring(dir.path.length);
      if (Platform.isWindows) {
        // replace windows file separators to URI separator as per rfc3986
        name = name.replaceAll(Platform.pathSeparator, '/');
      }
      if (excludeGlobs.any((glob) => glob.matches(name.substring(1)))) continue;
      if (name.endsWith('/$indexHtml')) {
        name = name.substring(0, name.length - indexHtml.length);
      }
      // making URLs relative
      name = '.$name';
      urls.add(name);
    }
  }

  return urls.toList()..sort();
}

/// Updates the offline_urls.g.dart file.
Future writeOfflineUrls(List<String> urls, String fileName) async {
  String listItems = urls.map((s) => '\'$s\',').join();
  String src = '''
    /// URLs for offline cache.
    final List<String> offlineUrls = [$listItems];
  ''';
  src = new DartFormatter().format(src);
  await _updateIfNeeded(fileName, src);
}

/// Detects the package name if lib-include is not set.
Future<String> detectLibInclude(ArgResults argv) async {
  String libInclude = argv['lib-include'];
  if (libInclude != null) return libInclude;
  File pubspec = new File('pubspec.yaml');
  if (pubspec.existsSync()) {
    var data = yaml.loadYaml(await pubspec.readAsString());
    if (data is Map) {
      return data['name'];
    }
  }
  return null;
}

/// Generates the PWA's worker script.
Future generateWorkerScript(ArgResults argv, String libInclude) async {
  String libDir = argv['lib-dir'];
  bool hasWorkerConfig = new File('$libDir/worker.dart').existsSync();

  String customImport =
      'import \'package:$libInclude/pwa/offline_urls.g.dart\' as offline;';
  String createWorker =
      'Worker worker = new Worker()..offlineUrls = offline.offlineUrls;';
  if (hasWorkerConfig) {
    customImport = 'import \'package:$libInclude/pwa/worker.dart\' as custom;';
    createWorker = 'Worker worker = custom.createWorker();';
  }

  String src = '''import 'package:pwa/worker.dart';
  $customImport

  /// Starts the PWA in the worker scope.
  void main() {
    $createWorker
    worker.run();
  }
  ''';
  src = new DartFormatter().format(src);

  await _updateIfNeeded('${argv['web-dir']}/pwa.g.dart', src);
}

Future _updateIfNeeded(String fileName, String content) async {
  File file = new File(fileName);
  if (file.existsSync()) {
    String oldContent = await file.readAsString();
    if (oldContent == content) {
      // No need to override the file
      return;
    }
  } else {
    await file.parent.create(recursive: true);
  }
  print('Updating $fileName.');
  await file.writeAsString(content);
}
