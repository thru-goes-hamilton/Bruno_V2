import 'package:bruno/chat_page_old.dart';
import 'package:bruno/constants.dart';
import 'package:flutter/material.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/file_icons.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  Bruno()), // Replace `NextPage` with the actual page you want to navigate to
        );
      },
      child: Container(
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width,
          color: kDarkPurple,
          padding: EdgeInsets.only(top: 18, left: 27, right: 27, bottom: 18),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                    tag: 'brainIcon',
                    child: Iconify(FileIcons.brainfuck,
                        size: 250, color: kWhitePurple)),
                SizedBox(height: 36),
                Hero(
                  tag: 'brunoText',
                  child: Text(
                    'BRUNO',
                    style: TextStyle(
                      color: kWhitePurple,
                      fontSize: 54,
                      fontFamily: 'Merriweather',
                    ),
                  ),
                )
              ],
            ),
          )),
    ));
  }
}
