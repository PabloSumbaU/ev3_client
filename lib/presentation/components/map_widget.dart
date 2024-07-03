import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import 'package:ev3_client/infrastructure/concurrent.dart';
import 'package:ev3_client/infrastructure/mapping.dart';
import 'package:logging/logging.dart';

final _log = Logger("Map Widget");

class MapWidget extends StatefulWidget {
  const MapWidget({super.key});
  
  @override
  State<StatefulWidget> createState() {
    _log.finest("Map widget created");
    return _MapWidgetState();
  }
}

class _MapWidgetState extends State<MapWidget> {
  static Worker<Commands, Future<ui.Image>>? mapWorker;
  ByteData? mapImageBytes;

  @override
  void initState() {
    super.initState();

    _log.finest("Initializing widget...");

    initializeWorker();

    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      updateMapImage();
    });
  }

  void initializeWorker() async {
    if(mapWorker != null) return;
    _log.finest("Worker not instantiated, creating instance...");
    mapWorker = await Map.startConcurrent();
  }

  void updateMapImage() async {
    if(mapWorker == null) return;
    //DON'T QUESTION IT, OK?
    ui.Image newMapImage = await await mapWorker!.send(Commands.render);
    ByteData? newImageBytes = await newMapImage.toByteData(format: ui.ImageByteFormat.png);
    
    setState(() {
      mapImageBytes = newImageBytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: mapImageBytes != null ? Image.memory(Uint8List.view(mapImageBytes!.buffer)) : const Placeholder(),
    );
  }
}