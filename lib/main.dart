import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  @override
  void initState() {
    super.initState();
    _loadNidsFromFirestore();
  }

  // ----- Géolocalisation -----
  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    return await Geolocator.getCurrentPosition();
  }

  Future<void> _centerOnUser() async {
    final pos = await _getCurrentLocation();
    if (pos != null) {
      final latLng = LatLng(pos.latitude, pos.longitude);
      _mapController.move(latLng, 15.0);
      _addMarker(latLng); // ajoute un marker sur la position
    }
  }

  // ----- Chargement des nids depuis Firestore -----
  Future<void> _loadNidsFromFirestore() async {
    final snapshot = await FirebaseFirestore.instance.collection('nids').get();
    final List<Marker> loadedMarkers = snapshot.docs.map((doc) {
      final data = doc.data();
      return Marker(
        point: LatLng(data['lat'], data['lng']),
        width: 80,
        height: 80,
        child: Icon(Icons.warning, color: Colors.red),
      );
    }).toList();

    setState(() {
      _markers.addAll(loadedMarkers);
    });
  }

  // ----- Ajouter un marker -----
  void _addMarker(LatLng pos) {
    final marker = Marker(
      point: pos,
      width: 80,
      height: 80,
      child: GestureDetector(
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

  // ----- Info popup -----
  void _showMarkerInfo(LatLng pos) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Info Nid'),
        content: Text('Position: ${pos.latitude}, ${pos.longitude}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text('Fermer')),
          TextButton(
              onPressed: () {
                setState(() {
                  _markers.removeWhere((m) => m.point == pos);
                });
                Navigator.pop(context);
              },
              child: Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // ----- Choix image utilisateur -----
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _userLogoBytes = bytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard Nid Poule'),
        actions: [
          IconButton(
            onPressed: _pickImage,
            icon: Icon(Icons.photo),
            tooltip: 'Choisir logo',
          )
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: LatLng(48.8566, 2.3522),
          initialZoom: 13.0,
          onTap: (tapPos, latlng) {
            if (latlng != null) _addMarker(latlng);
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.example.nid_poule_app',
          ),
          MarkerClusterLayerWidget(
            options: MarkerClusterLayerOptions(
              maxClusterRadius: 120,
              size: const Size(50, 50),
              markers: _markers,
              builder: (context, markers) {
                return Container(
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${markers.length}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'user_location',
            onPressed: _centerOnUser,
            child: Icon(Icons.my_location),
            tooltip: 'Ma position',
          ),
          SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'add_marker',
            onPressed: () {
              // Ajoute un marker au centre actuel
              final center = _mapController.center;
              _addMarker(center);
            },
            child: Icon(Icons.add_location),
            tooltip: 'Ajouter Nid au centre',
          ),
        ],
      ),
    );
  }
}