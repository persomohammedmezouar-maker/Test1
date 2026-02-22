import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';

void main() {
  runApp(NidPouleApp());
}

class NidPouleApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nid Poule App',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        brightness: Brightness.light,
      ),
      home: NidDashboardScreen(),
    );
  }
}

class NidDashboardScreen extends StatefulWidget {
  @override
  _NidDashboardScreenState createState() => _NidDashboardScreenState();
}

class _NidDashboardScreenState extends State<NidDashboardScreen> {
  final MapController _mapController = MapController();
  final List<Marker> _markers = [];
  Uint8List? _userLogoBytes;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _userLogoBytes = bytes;
      });
    }
  }

  void _addMarker(LatLng pos) {
    final marker = Marker(
      point: pos,
      width: 80,
      height: 80,
      builder: (ctx) => GestureDetector(
        onTap: () => _showMarkerInfo(pos),
        child: _userLogoBytes != null
            ? Image.memory(_userLogoBytes!)
            : Icon(Icons.location_on, size: 40, color: Colors.red),
      ),
    );
    setState(() {
      _markers.add(marker);
    });
  }

  void _showMarkerInfo(LatLng pos) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: Text('Info Nid'),
              content: Text('Position: ${pos.latitude}, ${pos.longitude}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Fermer')),
                TextButton(
                    onPressed: () {
                      setState(() {
                        _markers.removeWhere((m) => m.point == pos);
                      });
                      Navigator.pop(context);
                    },
                    child: Text('Supprimer', style: TextStyle(color: Colors.red))),
              ],
            ));
  }

  LatLng _getMapCenter() {
    try {
      final bounds = _mapController.bounds;
      if (bounds != null) {
        return LatLng(
          (bounds.north + bounds.south) / 2,
          (bounds.east + bounds.west) / 2,
        );
      }
    } catch (e) {}
    return LatLng(48.8566, 2.3522); // fallback
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard Nid Poule'),
        actions: [IconButton(onPressed: _pickImage, icon: Icon(Icons.photo))],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          center: LatLng(48.8566, 2.3522),
          zoom: 13.0,
          onTap: (tapPos, latlng) {
            if (latlng != null) _addMarker(latlng);
          },
        ),
        children: [
          TileLayer(
            urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            subdomains: ['a', 'b', 'c'],
            userAgentPackageName: 'com.example.nid_poule_app',
          ),
          MarkerClusterLayerWidget(
            options: MarkerClusterLayerOptions(
              maxClusterRadius: 120,
              size: Size(50, 50),
              markers: _markers,
              builder: (context, markers) {
                return Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: Colors.orange, shape: BoxShape.circle),
                  child: Text('${markers.length}',
                      style: TextStyle(color: Colors.white)),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final center = _getMapCenter();
          _addMarker(center);
        },
        child: Icon(Icons.add_location),
        tooltip: 'Ajouter Nid',
      ),
    );
  }
}
