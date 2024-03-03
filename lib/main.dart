import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:installed_apps/app_info.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:io' as io;
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record_mp3/record_mp3.dart';
import 'package:path_provider/path_provider.dart';
import 'package:installed_apps/installed_apps.dart';
import 'dart:isolate';

void main() {
  runApp(MyApp());
}

@pragma('vm:entry-point')
  void _callback(NotificationEvent evt) {
      // persist data immediately
    final SendPort? send = IsolateNameServer.lookupPortByName("_listener_");
    if(send == null) print("can't find sender");
    send?.send(evt);
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
  bool isRecording = false;
  List<AppInfo> monitoredApps = [];
  List<AppInfo> installedApps = [];
  void _getInstalledApps() async {
    installedApps = await InstalledApps.getInstalledApps(true, true, "");

  }

  ReceivePort port = ReceivePort();

  @override
  void initState() {
    super.initState();
    _getContacts();
    _getInstalledApps();
    initPlatformState();
    startListening();
  }

  

  void onData(NotificationEvent event) async {
    int index = monitoredApps.indexWhere((obj) => obj.packageName == event.packageName);
    print(monitoredApps);
    if(index != -1)
    {
      String contactName = event?.title ?? '';
      print(contactName);
      print(event?.text ?? "");
      for(Contact c in contacts)
      {
        if(c.displayName == contactName)
        {
          if(c.notes.last != null) {
            String rawNote = c.notes.last.note;
            String filePath = '';
            int colindex = rawNote.indexOf(":");
            filePath = '${await getFilePath()}${rawNote.substring(colindex+1).trim()}';
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
                var d = io.Directory('${await getFilePath()}/res/');
                if (!d.existsSync()) {
                  d.createSync(recursive: true);
                }
                String resFilePath = '${await getFilePath()}/res/${c.displayName}001.mp3';
                var transferredAudio = io.File(resFilePath);
                io.IOSink sink = transferredAudio.openWrite();
                await sink.addStream(response.stream);
                await sink.close();
                final player = AudioPlayer();
                await player.setUrl('file://${resFilePath}');
                await player.play();
                await player.stop();
              }
            });
          }
        }
      }
    }
  }

  Future<void> initPlatformState() async {
      NotificationsListener.initialize(callbackHandle: _callback);
      IsolateNameServer.removePortNameMapping("_listener_");
      IsolateNameServer.registerPortWithName(port.sendPort, "_listener_");
      port.listen((evt) => onData(evt));
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
      Iterable<Contact> allContacts = await FlutterContacts.getContacts(withProperties: true, withPhoto: true, withAccounts: true);
      setState(() {
        contacts = allContacts.toList();
      });
    } else {
      // Handle permission denied
      print('Contacts permission denied');
    }
  }

  Future<String> getFilePath() async {
    io.Directory storageDirectory = await getApplicationDocumentsDirectory();
    String sdPath = '${storageDirectory.path}';
    var d = io.Directory(sdPath);
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
    return sdPath;
  }

  Future<void> _openAudioDialog(Contact selectedContact) async {
    // Show dialog with options
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text('Select or Record Audio for ${selectedContact.displayName}'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    // Open file picker to select audio file
                    FilePickerResult? result =
                        await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['mp3', 'aac'],
                    );

                    if (result != null) {
                      setState(() {
                        // Store the audio path for the selected contact
                        selectedContact.notes[0].note = 'Voice Note: ${result.files.single.path!}';
                      });
                    }

                    Navigator.pop(context); // Close the dialog
                  },
                  child: Text('Select Audio File'),
                ),
                SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                      // Start recording audio
                      if(!isRecording)
                      {
                        String recordPath = await getFilePath();
                        
                        bool micPermission = await Permission.microphone.isGranted;
                        PermissionStatus status;
                        if(!micPermission) {
                          status = await Permission.microphone.request();
                        }
                        else {
                          status = PermissionStatus.granted;
                        }

                        if(status == PermissionStatus.granted)
                        {
                          RecordMp3.instance.start('$recordPath/record/${selectedContact.displayName.trim()}001.mp3', (type){});
                          setState(() {
                            isRecording = true;
                          });
                        }
                      }
                      else {
                        RecordMp3.instance.stop();
                        bool noteExists = false;
                        Note existingNote = Note('');
                        for(Note note in selectedContact.notes)
                        {
                          if(note.note.contains('Voice Note')) {
                            noteExists = true;
                            existingNote = note;
                          }
                        }
                        if(noteExists) {
                          existingNote.note = 'Voice Note: /record/${selectedContact.displayName.trim()}001.mp3';
                        }
                        else
                        {
                          selectedContact.notes.add(Note('Voice Note: /record/${selectedContact.displayName.trim()}001.mp3'));
                        }
                        setState(() {
                          // Store the audio path for the selected contact
                          isRecording = false;
                        });
                        await selectedContact.update();
                        Navigator.pop(context); // Close the dialog
                      }
                    },
                  child: Text(isRecording ? 'Stop Recording' : 'Start Recording'),
                  ),
                ],
              ),
            );
          },
        );
      }
    );
  }

  int _selectedIndex = 0;
  final List<String> _destinations = ['Contacts', 'Settings', 'About'];

  Widget _buildNavigationRail() {
    return NavigationRail(
      labelType: NavigationRailLabelType.selected,
      selectedIndex: _selectedIndex,
      onDestinationSelected: (int index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      destinations: const <NavigationRailDestination>[
        NavigationRailDestination(
          icon: Icon(Icons.contact_page_outlined),
          selectedIcon: Icon(Icons.contact_page),
          label: Text('Contacts'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.info_outline),
          selectedIcon: Icon(Icons.info),
          label: Text('About'),
        ),
      ],
    );
  }

  Widget _buildContactPage() {
    return Expanded(
            child: ListView.builder(
              itemCount: contacts.length,
              itemBuilder: (context, index) {
                Contact contact = contacts[index];
                return Padding(
                  padding: const EdgeInsets.all(9.0),
                  child: Card(
                    elevation: 4.0,
                    color: Colors.grey[100],
                    child: ListTile(
                      title: Text(
                        contact.displayName ?? '',
                        style: TextStyle(
                          fontSize: 18.0,
                          fontWeight: FontWeight.w400,
                          color: Colors.black,
                        ),
                      ),
                      subtitle: Text(contact.notes.lastOrNull?.note ?? 'No note'),
                      onTap: () {
                        _openAudioDialog(contact);
                      }
                    ),
                  ),
                );
              },
            ),
          );
  }

  Widget _buildAboutPage() {
    return Expanded(
      child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Add your logo here
              Image.asset('assets/images/logo.png'),
              const SizedBox(height: 16.0),
              const SizedBox(height: 8.0),
              const Text(
                'Version 0.0.0a',
                style: TextStyle(
                  fontSize: 18.0,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16.0),
              const Text(
                'Persona is a text-to-speech app that puts a human touch to spoken notifications.',
                style: TextStyle(fontSize: 16.0),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
    );
  }

  


  Widget _buildSettingsPage() {


    return Expanded(
      child: ListView.builder(
          itemCount: installedApps.length,
          itemBuilder: (context, index) {
            AppInfo appId = installedApps[index]; 
            bool isSelected = monitoredApps.contains(appId);
      
            return ListTile(
              title: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 20, 0),
                    child: Image.memory(appId.icon!, width: 30),
                  ),
                  Flexible(child: Text(appId.name, overflow: TextOverflow.fade)),
                ],
              ),
              trailing: Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value != null) {
                      if (value) {
                        monitoredApps.add(appId);
                      } else {
                        monitoredApps.remove(appId);
                      }
                    }
                  });
                },
              ),
            );
          },
        ),
      );
  }


  @override
  Widget build(BuildContext context) {
    Widget returnWidget = Text('');
    if(_selectedIndex == 0)
    {
      returnWidget = _buildContactPage();
    }
    if(_selectedIndex == 1)
    {
      returnWidget = _buildSettingsPage();
    }
    if(_selectedIndex == 2)
    {
      returnWidget = _buildAboutPage();
    }
    return Scaffold(
      backgroundColor: Colors.amberAccent[50],
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0),
          child: Text('Persona()'),
        ),
      ),
      body: Row(
        children: [
          _buildNavigationRail(),
          returnWidget,
        ],
      ),
    );
  }
}

