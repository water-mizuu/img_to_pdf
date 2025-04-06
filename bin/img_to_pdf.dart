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

const String inputFolder = "assets/input/";
const String outputFolder = "assets/output/";

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
  static const int max = 2;

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
    List<File> files = await children //
        .whereType<File>()
        .where(entityIsImage)
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    for (File child in files) {
      Uint8List rawImageData = child.readAsBytesSync();
      MemoryImage imageData = MemoryImage(rawImageData);

      double width = imageData.width!.toDouble();
      double height = imageData.height!.toDouble();

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

  try {
    String? mimeType = mime.lookupMimeType(entity.path);

    return mimeType != null && mimeType.split("/").first == "image";
  } on Object {
    print(entity.path);

    return false;
  }
}

void main() async {
  List<String> bookDirectories = Directory(inputFolder) //
      .listSync()
      .whereType<Directory>()
      .map((Directory dir) => dir.path)
      .toList();

  var batches = bookDirectories.group(BookBatch.max).toList();

  print("Running ${batches.length} batches of ${BookBatch.max} books each.");
  for (var (index, bookPaths) in batches.indexed) {
    print("Batch $index has been started.");
    await BookBatch(bookPaths).createBooks();
    print("Batch $index has been finished.");
  }
}
