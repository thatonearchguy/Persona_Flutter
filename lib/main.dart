import 'dart:html';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:http_parser/http_parser.dart';
import 'dart:io' as io;
import 'package:just_audio/just_audio.dart';


void main() {
  runApp(MyApp());
}


@pragma('vm:entry-point')
void _callback(NotificationEvent evt) {
    // persist data immediately
    

}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Contact> contacts = [];

  @override
  void initState() {
    super.initState();
    _getContacts();
  }


  void onData(NotificationEvent event) async {
      String contactName = event?.title ?? '';
      for(Contact c in contacts)
      {
        if(c.displayName == contactName)
        {
          if(c.notes.first != null) {
            String rawNote = c.notes.first.note;
            String filePath = '';
            int colindex = rawNote.indexOf(":");
            filePath = rawNote.substring(colindex+1).trim();
            var request = new http.MultipartRequest("POST", Uri?.tryParse("http://juan289flerovium.pythonanywhere.com/") ?? Uri());
            request.fields['text'] = event?.text ?? "";
            request.files.add(await http.MultipartFile.fromPath(
              'file',
              filePath, 
              contentType: MediaType('application', 'mp3'),
            ));
            request.send().then((response) async {
              if(response.statusCode == 200)
              {
                print ("Success!");
                String resFilePath = 'res${filePath}';
                var transferredAudio = io.File('someFile');
                io.IOSink sink = transferredAudio.openWrite();
                await sink.addStream(response.stream);
                await sink.close();
                final player = AudioPlayer();
                final duration = await player.setUrl('file://${resFilePath}');
                await player.play();
              }
            });
          }

        }
      }
  }

  Future<void> initPlatformState() async {
      NotificationsListener.initialize(callbackHandle: _callback);
      NotificationsListener.receivePort?.listen((evt) => onData(evt));
  }


  void startListening() async {
      print("start listening");
      var hasPermission = await NotificationsListener.hasPermission;
      if(hasPermission != null)
      {
        if (!hasPermission) {
            print("no permission, so open settings");
            NotificationsListener.openPermissionSettings();
            return;
        }
      }

      var isR = await NotificationsListener.isRunning;
      if(isR != null)
      {
        if (!isR) {
            await NotificationsListener.startService(
              foreground: false,
              title: 'Custom TTS Active',
              description: 'Listening for notifications'
            );
        }
      }
  }

  Future<void> _getContacts() async {
    // Request permission
    PermissionStatus permissionStatus = await Permission.contacts.request();

    if (permissionStatus.isGranted) {
      // Get all contacts
      Iterable<Contact> allContacts = await FlutterContacts.getContacts(withProperties: true, withPhoto: false);
      setState(() {
        contacts = allContacts.toList();
      });
    } else {
      // Handle permission denied
      print('Contacts permission denied');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Assign voices'),
      ),
      body: ListView.builder(
        itemCount: contacts.length,
        itemBuilder: (context, index) {
          Contact contact = contacts[index];
          return ListTile(
            title: Text(contact.displayName ?? ''),
            subtitle: Text(contact.notes.firstOrNull?.note ?? 'No note'),
          );
        },
      ),
    );
  }
}