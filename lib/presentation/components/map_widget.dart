import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ev3_client/infrastructure/concurrent.dart';
import 'package:ev3_client/infrastructure/mapping.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';

final _log = Logger("Map Widget");

// TODO: Restart mapping on reconnection

class MapWidget extends StatefulWidget {
  const MapWidget({super.key});

  static void terminate() {
    _MapWidgetState.mapWorker?.terminate();
  }
  
  @override
  State<StatefulWidget> createState() {
    return _MapWidgetState();
  }
}

class _MapWidgetState extends State<MapWidget> {
  static Worker<Commands, img.Image>? mapWorker;
  Uint8List? mapImageBytes;

  @override
  void initState() {
    super.initState();

    _log.finest("Initializing widget...");

    initializeWorker();

    Timer.periodic(const Duration(milliseconds: TerrainMap.timeBetweenUpdates), (timer) {
      updateMapImage();
    });
  }

  void initializeWorker() async {
    if(mapWorker != null) return;
    _log.finest("Worker not instantiated, creating instance...");
    mapWorker = await TerrainMap.startConcurrent();
  }

  void updateMapImage() async {
    if(mapWorker == null) return;
    
    img.Image image = await mapWorker!.send(Commands.render);

    Uint8List newImageBytes = img.PngEncoder().encode(image);
    setState(() {
      mapImageBytes = newImageBytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: const BorderRadius.all(Radius.circular(2.0))
      ),
      child: SizedBox(
        width: TerrainMap.mapSize.toDouble(), 
        height: TerrainMap.mapSize. toDouble(),
        child: mapImageBytes != null ? Image.memory(mapImageBytes!, gaplessPlayback: true) : const CircularProgressIndicator(),
      )
    );
  }

  @override
  void dispose() {
    super.dispose();
    mapWorker?.terminate();
  }
}