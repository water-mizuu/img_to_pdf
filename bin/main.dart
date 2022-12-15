import "dart:async";
// import "dart:collection";
import "dart:io";
import "dart:isolate";
import "dart:math" as math;
import "dart:typed_data";

import "package:mime/mime.dart" as mime;
import "package:path/path.dart" as path;
import "package:pdf/pdf.dart";
import "package:pdf/widgets.dart";

const String inputFolder = r"assets\input\";
const String outputFolder = r"assets\output\";

extension ListGroupExtension<E> on List<E> {
  Iterable<List<E>> group(int length) sync* {
    int groupCount = (this.length / length).ceil();
    for (int i = 0; i < groupCount; i++) {
      int upperBound = (i + 1) * length;
      List<E> slice = sublist(i * length, math.min(this.length, upperBound));
      yield slice;
    }
  }
}

extension IterableEnumerateExtension<E> on Iterable<E> {
  Iterable<(int, E)> entries() sync* {
    int i = 0;
    for (E item in this) {
      yield (i, item);
    }
  }
}

extension StreamTypeExtension<E> on Stream<E> {
  Stream<R> whereType<R>() async* {
    await for (E item in this) {
      if (item is R) {
        yield item;
      }
    }
  }
}

class BookBatch {
  static const int max = 8;

  final List<String> bookPaths;

  BookBatch(this.bookPaths);

  Future<void> createBooks() async {
    int finished = 0;
    Completer<void> completer = Completer<void>();
    for (String bookPath in bookPaths) {
      Isolate bookIsolate = await Isolate.spawn(createPdfForBook, bookPath);
      ReceivePort killReceivePort = ReceivePort();
      killReceivePort.listen((void _) {
        bookIsolate.kill(); // Kill the isolate
        killReceivePort.close(); // Close the sink
        finished++;

        if (finished >= bookPaths.length) {
          completer.complete();
        }
      });

      bookIsolate.addOnExitListener(killReceivePort.sendPort);
    }

    return completer.future;
  }

  static void createPdfForBook(String inputPath) async {
    String exportName = path.basename(inputPath);
    String exportPath = path.join(outputFolder, "$exportName.pdf");

    File exportPdfFile = File(exportPath)..createSync(recursive: true);

    Document document = Document();
    Stream<FileSystemEntity> children = Directory(inputPath).list();

    await for (File child in children.where(entityIsImage).whereType<File>()) {
      Uint8List rawImageData = child.readAsBytesSync();
      MemoryImage imageData = MemoryImage(rawImageData);

      double? width = imageData.width?.toDouble();
      double? height = imageData.height?.toDouble();

      if (width == null || height == null) {
        continue;
      }

      document.addPage(
        Page(
          build: (_) => Image(imageData),
          pageFormat: PdfPageFormat(width, height, marginAll: 0),
        ),
      );
    }

    Uint8List bytes = await document.save();
    await exportPdfFile.writeAsBytes(bytes);
  }
}

bool entityIsImage(FileSystemEntity entity) {
  if (entity is! File) {
    return false;
  }
  String? mimeType = mime.lookupMimeType(entity.path);

  return mimeType != null && mimeType.split("/").first == "image";
}

void main() async {
  List<String> bookDirectories = Directory(inputFolder) //
      .listSync()
      .whereType<Directory>()
      .map((Directory dir) => dir.path)
      .toList();

  for (var batch in bookDirectories.group(BookBatch.max).entries()) {
    print("Batch ${batch.$0} has been started.");
    await BookBatch(batch.$1).createBooks();
    print("Batch ${batch.$0} has been finished.");
  }
}
