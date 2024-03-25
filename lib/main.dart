import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(
        title: 'หน้าแรก',
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  dynamic controller;
  bool isBusy = false;
  late Size size;

  static const TextStyle optionStyle =
  TextStyle(fontSize: 30, fontWeight: FontWeight.bold);

  Timer? speakTimer;
  @override
  void initState() {
    super.initState();
    initializeCamera();
    // ส่งเสียงเมื่อเแอปเริ่มทำงาน
    speak("ยินดีต้อนรับสู่แอปตรวจจับวัตถุสำหรับผู้พิการทางสายตา");

    // เรียกใช้ฟังก์ชันส่งเสียงชื่อวัตถุที่จำแนกได้ทุก ๆ 3 วินาที
    speakTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      speakDetectedObjectLabel();
    });

  }

  //ส่วนของการส่งเสียงชื่อวัตถุที่จำแนกได้
  void speakDetectedObjectLabel() {
    //เช็คผลลัพท์ของการจำแนกวัตถุ
    if (_scanResults != null && _scanResults.isNotEmpty) {
      var firstObject = _scanResults[0];

      if (firstObject != null
          && firstObject.labels != null
          && firstObject.labels.isNotEmpty) {
        var firstLabel = firstObject.labels[0];

        if (firstLabel.text != null && firstLabel.text.isNotEmpty) {
          //ส่งเสียงชื่อของวัตถุที่จำแนกได้
          speak(firstLabel.text);
        }
      }
    }
  }

  final FlutterTts flutterTts = FlutterTts();
  //ฟังก์ชันการส่งเสียงด้วย Text to speak
  speak(String text) async {
    await flutterTts.awaitSpeakCompletion(true);
    await flutterTts.setLanguage("th-TH");
    await flutterTts.setSpeechRate(0.6);
    await flutterTts.speak(text);
  }

  //ส่วนของโครงการแสดงผลของหน้าจอแอปพลิเคชัน
  @override
  Widget build(BuildContext context) {
    List<Widget> stackChildren = [];
    size = MediaQuery.of(context).size;
    //แสดงผลลัพท์ของกล้อง
    if (controller != null) {
      stackChildren.add(
        Positioned(
          top: 0.0,
          left: 0.0,
          width: size.width,
          height: size.height,
          child: Container(
            child: (controller.value.isInitialized)
                ? AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: CameraPreview(controller),
            )
                : Container(),
          ),
        ),
      );
      stackChildren.add(
        Positioned(
            top: 0.0,
            left: 0.0,
            width: size.width,
            height: size.height,
            child: buildResult()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text("แอปตรวจจับวัตถุสำหรับผู้พิการทางสายตา"),//แสดงบนส่วนบนสุดของแอป
        backgroundColor: Colors.blue,
      ),
      backgroundColor: Colors.black,
      body: Container(
          margin: const EdgeInsets.only(top: 0),
          color: Colors.black,
          child: Stack(
            children: stackChildren,
          )
      ),
    );
  }


  dynamic objectDetector;// ตัวแปรที่ใช้เก็บการตั้งค่าเพื่อตรวจจับวัตถุ
  //เริ่มต้นในการตั้งค่าเพื่อตรวจจับและจำแนกวัตถุ
  initializeCamera() async {
    //เรียกใช้งานฟังก์ชันเก็บค่า path ของโมเดลจำแนกวัตถุ
    final modelPath = await _getModel('assets/ml/ef4_0306.tflite');
    final options = LocalObjectDetectorOptions(
      modelPath: modelPath,
      classifyObjects: true, //การจำแนกวัตถุ
      multipleObjects: false, //จำกัดให้ตรวจได้เพียงเดียวต่อรูป
      mode: DetectionMode.stream //โหมดการตรวจจับแบบวิดิโอ
    );
    objectDetector = ObjectDetector(options: options);

    controller = CameraController(cameras[0], ResolutionPreset.high);
    await controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      controller.startImageStream((image) => {
            if (!isBusy)
              //เรียกใช้งานฟังก์ชันตรวจจับวัตถุ
              {isBusy = true, img = image, doObjectDetectionOnFrame()}
          });
    });
  }
  //ส่วนของฟังก์ชันเก็บค่า path โมเดลจำแนกวัตถุ
  Future<String> _getModel(String assetPath) async {
    if (Platform.isAndroid) {
      return 'flutter_assets/$assetPath';
    }
    final path = '${(await getApplicationSupportDirectory()).path}/$assetPath';
    await Directory(dirname(path)).create(recursive: true);
    final file = File(path);
    if (!await file.exists()) {
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return file.path;
  }

  //close all resources
  @override
  void dispose() {
    // Cancel the timer when the widget is disposed
    speakTimer?.cancel();
    controller?.dispose();
    objectDetector.close();
    super.dispose();
  }

  dynamic _scanResults; //ตัวแปรที่เก็บผลลัพท์ของการตรวจจับและจำแนกวัตถุ
  CameraImage? img;
  //ฟังก์ชันตรวจจับวัตถุและจำแนกวัตถุจากกล้องโทรศัพท์
  doObjectDetectionOnFrame() async {
    var frameImg = getInputImage();// รับค่ารูปภาพจากกล้องโทรศัพท์

    //ประมวลผลลัพท์ของการตรวจจับและจำแนกวัตถุ
    List<DetectedObject> objects = await objectDetector.processImage(frameImg);

    setState(() {
      _scanResults = objects;//เก็บผลลัพท์พื่อใช้งานในฟังก์ชันอื่น ๆ
    });
    isBusy = false;
  }

  //ฟังก์ชันรับรูปภาพจากกล้องโทรศัพท์
  InputImage getInputImage() {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in img!.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    final Size imageSize = Size(img!.width.toDouble(), img!.height.toDouble());
    final camera = cameras[0];
    final imageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    final inputImageFormat =
        InputImageFormatValue.fromRawValue(img!.format.raw);

    final planeData = img!.planes.map(
      (Plane plane) {
        return InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      },
    ).toList();

    final inputImageData = InputImageData(
      size: imageSize,
      imageRotation: imageRotation!,
      inputImageFormat: inputImageFormat!,
      planeData: planeData,
    );
    final inputImage =
        InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);
    return inputImage;
  }

  //แสดงผลลัพท์จากการตรวจจับวัตถุบนหน้าจอแสดงผล
  Widget buildResult() {
    //หากไม่พบวัตถุ
    if (_scanResults == null || controller == null || !controller.value.isInitialized) {
      return Text('');
    }
    final Size imageSize = Size(
      controller.value.previewSize!.height,
      controller.value.previewSize!.width,
    );
    //เรียกใช้ฟังก์ชันแสดงผลวัตถุที่กำลังตรวจจับ
    CustomPainter painter = ObjectDetectorPainter(imageSize, _scanResults);
    return CustomPaint(
      painter: painter,
    );
  }
}
//ฟังก์ชันแสดงผลวัตถุที่กำลังตรวจจับ (รูปแบบสี่เหลี่ยมรอบวัตถุที่กำลังตรวจจับ)
class ObjectDetectorPainter extends CustomPainter {
  ObjectDetectorPainter(this.absoluteImageSize, this.objects);
  final Size absoluteImageSize;
  final List<DetectedObject> objects;
  @override
  //เริ่มต้นการตั้งค่าเพื่อแสดงผล
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / absoluteImageSize.width;
    final double scaleY = size.height / absoluteImageSize.height;
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.blue;
    for (DetectedObject detectedObject in objects) {
      canvas.drawRect(Rect.fromLTRB(
          detectedObject.boundingBox.left * scaleX,
          detectedObject.boundingBox.top * scaleY,
          detectedObject.boundingBox.right * scaleX,
          detectedObject.boundingBox.bottom * scaleY,
        ), paint,
      );
      var list = detectedObject.labels;
      for (Label label in list) {
        //รับค่าชื่อของวัตถุที่จำแนกได้
        var showText = label.text;
        //เช็คว่าหากไม่พบวัตถุที่จำแนกได้ ไม่ต้องชื่อวัตถุ
        if(label.text == null || label.text.isEmpty){
          showText = "";
        }
        TextSpan span = TextSpan(
            text: showText,
            style: const TextStyle(fontSize: 25, color: Colors.blue));
        TextPainter tp = TextPainter(
            text: span,
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas,
            Offset(detectedObject.boundingBox.left * scaleX,
                detectedObject.boundingBox.top * scaleY));
        break;
      }
    }
  }

  @override
  bool shouldRepaint(ObjectDetectorPainter oldDelegate) {
    return oldDelegate.absoluteImageSize != absoluteImageSize ||
        oldDelegate.objects != objects;
  }
}
