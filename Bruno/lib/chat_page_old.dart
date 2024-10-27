import 'dart:convert';

import 'package:bruno/chat_components.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/file_icons.dart';
import 'package:iconify_flutter/icons/carbon.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';


import 'constants.dart';

class Bruno extends StatefulWidget {
  const Bruno({super.key});

  @override
  State<Bruno> createState() => _BrunoState();
}

class _BrunoState extends State<Bruno> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  List<ChatMessage> messages = [];
  bool isLoading = false;
  bool isUploading = false;
  bool isDeleting = false;
  bool isFirstUpload = true;
  String? fileName;
  String? fileType;
  String? cacheFileName;

  Future<void> uploadFile() async {
    setState(() {
      isUploading = true;
    });

    if (fileName != null) {
      setState(() {
        isFirstUpload = false;
      });
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
      );

      if (result != null) {
        var file = result.files.single;
        fileName = file.name;
        fileType = file.extension;

        var request = http.MultipartRequest(
          'POST',
          Uri.parse('https://bruno-v2.onrender.com/upload'),
        );

        request.files.add(
          http.MultipartFile.fromBytes('file', file.bytes!,
              filename: file.name),
        );

        var response = await request.send();

        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context as BuildContext).showSnackBar(
            SnackBar(content: Text('File uploaded successfully')),
          );
        } else {
          throw Exception('Failed to upload file');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error uploading file: $e')),
      );
    } finally {
      setState(() {
        isUploading = false;
      });
    }
  }

  Future<void> deleteFile(String fileName) async {
    setState(() {
      isDeleting = true;
    });

    try {
      final response = await http.delete(
        Uri.parse('https://bruno-v2.onrender.com/delete/$fileName'),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(content: Text('File deleted successfully')),
        );
      } else {
        throw Exception('Failed to delete file');
      }
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error deleting file: $e')),
      );
    } finally {
      setState(() {
        isDeleting = false;
      });
    }
  }

  Future<void> sendQuery() async {
    String prompt = _controller.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Please enter a prompt')),
      );
      return;
    }

    setState(() {
      isLoading = true; // Show loading state
    });

    // Add the user prompt to the messages list
    messages.add(ChatMessage(prompt: prompt, answer: ''));
    _controller.clear(); // Clear the text field

    // Call the FastAPI endpoint
    try {
      print("Sending request to backend...");
      var response = await http.Client().send(http.Request(
        'POST',
        Uri.parse(
            'https://bruno-v2.onrender.com/query?prompt=$prompt'), // Ensure prompt is passed correctly
      ));

      // Stream the response
      response.stream.transform(utf8.decoder).listen((data) {
        print("Recieved data chunk: $data");
        setState(() {
          // Update the last message's answer with the streamed data
          messages[messages.length - 1].answer += data;
        });
      }, onDone: () {
        print("Stream completed");
        setState(() {
          isLoading = false;
          // messages[messages.length - 1].answer// Hide loading state when done
        });
      }, onError: (error) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
        setState(() {
          isLoading = false; // Hide loading state on error
        });
      });
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error sending query: $e')),
      );
      setState(() {
        isLoading = false; // Hide loading state on error
      });
    }
  }

  Future<void> extractAndVectorize() async {
    try {
      var response = await http.post(
        Uri.parse('https://bruno-v2.onrender.com/extract-and-vectorize'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
      );

      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(content: Text(jsonResponse['message'])),
        );
      } else {
        throw Exception('Failed to extract and vectorize: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> truncateDatabase() async {
    try {
      // Send the HTTP POST request to the truncate endpoint
      final response = await http.post(
        Uri.parse('https://bruno-v2.onrender.com/truncate'),
      );

      // Check if the response indicates success
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(content: Text('Database truncated successfully')),
        );
      } else {
        throw Exception('Failed to truncate database');
      }
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error truncating database: $e')),
      );
    }
  }

  Future<void> deleteAllFiles() async {
    try {
      // Send the HTTP DELETE request to the delete-all endpoint
      final response = await http.delete(
        Uri.parse('https://bruno-v2.onrender.com/delete-all'),
      );

      // Check if the response indicates success
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(content: Text('All files deleted successfully')),
        );
      } else {
        throw Exception('Failed to delete all files');
      }
    } catch (e) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Error deleting files: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // This is called when the app is being closed
      deleteAllFiles();
      truncateDatabase();
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        color: kDarkPurple,
        padding: EdgeInsets.only(top: 18, left: 27, right: 27, bottom: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                  tag: 'brainIcon',
                  child: Iconify(FileIcons.brainfuck,
                      size: 30, color: kLighterWhitePurple),
                ),
                SizedBox(width: 20),
                Hero(
                  tag: 'brunoText',
                  child: Text(
                    'BRUNO',
                    style: TextStyle(
                      color: kLighterWhitePurple,
                      fontSize: 26,
                      fontFamily: 'Merriweather',
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 200, vertical: 9),
                child: Column(
                  children: [
                    Expanded(
                      child: DynamicChatList(
                        messages: messages,
                        isLoading: isLoading,
                      ),
                    ),
                    fileName != null
                        ? Row(
                            children: [
                              SizedBox(
                                width: 18,
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4.5),
                                child: Chip(
                                  backgroundColor: kLightPurple,
                                  deleteIcon: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: kLighterWhitePurple,
                                  ),
                                  onDeleted: () {
                                    deleteFile(fileName!);
                                    setState(() {
                                      fileName = null;
                                    });
                                  },
                                  avatar: Icon(
                                    Icons.insert_drive_file,
                                    size: 18,
                                    color: kLighterWhitePurple,
                                  ),
                                  label: Text(
                                    fileName!.length > 8
                                        ? fileName!.substring(0, 8) + '...'
                                        : fileName!,
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontFamily: "MerriweatherSans",
                                        color: kLighterWhitePurple),
                                  ),
                                ),
                              ),
                              Expanded(child: SizedBox()),
                            ],
                          )
                        : SizedBox(height: 0),
                    Stack(
                      children: [
                        Container(
                          constraints: BoxConstraints(
                            maxHeight:
                                150, // Set a maximum height for the text field
                          ),
                          padding: EdgeInsets.symmetric(horizontal: 25),
                          decoration: BoxDecoration(
                            color: kWhitePurple,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: TextField(
                            controller: _controller,
                            maxLines: null, // Allow multiple lines
                            keyboardType: TextInputType
                                .multiline, // Enable multiline input
                            textInputAction: TextInputAction
                                .newline, // Use newline action for enter key
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 15),
                              hintText: "Talk to Bruno...",
                              hintStyle: TextStyle(
                                color: kDarkPurple,
                                fontSize: 18,
                                fontFamily: 'MerriweatherSans',
                              ),
                              border: InputBorder.none,
                            ),
                            style: TextStyle(
                              color: kDarkPurple,
                              fontSize: 18,
                              fontFamily: 'MerriweatherSans',
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: kLightPurple,
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: IconButton(
                                  icon: isUploading
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    kWhitePurple),
                                          ),
                                        )
                                      : Iconify(Ic.round_attach_file,
                                          size: 20, color: kWhitePurple),
                                  onPressed: isUploading ? null : uploadFile,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                              SizedBox(width: 4.5),
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: kDarkPurple,
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: IconButton(
                                  icon: Iconify(Carbon.send_filled,
                                      size: 20, color: kWhitePurple),
                                  onPressed: () {
                                    setState(() async {
                                      await sendQuery();
                                    });
                                  },
                                ),
                              ),
                              SizedBox(width: 4.5),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
