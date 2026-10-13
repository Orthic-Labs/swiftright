#include <Security/Security.h>
#include <Security/AuthSession.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
int main(int argc, char **argv) {
  if (argc != 2 || strncmp(argv[1], "/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr0/tuple12-recorder-signed-r1/", 81) != 0) { fprintf(stderr,"exclusive internal app path required\n"); return 64; }
  OSStatus create = SessionCreate(0, 0);
  SecuritySessionId sid = 0; SessionAttributeBits attr = 0;
  OSStatus info = SessionGetInfo(callerSecuritySession, &sid, &attr);
  OSStatus ui = SecKeychainSetUserInteractionAllowed(false);
  Boolean allowed = true; OSStatus uiCheck = SecKeychainGetUserInteractionAllowed(&allowed);
  printf("{\"phase\":\"signer-session-preflight\",\"createStatus\":%d,\"infoStatus\":%d,\"securitySessionID\":%u,\"attributes\":%u,\"graphicAccess\":%s,\"ttyAccess\":%s,\"setInteractionStatus\":%d,\"getInteractionStatus\":%d,\"interactionAllowed\":%s}\n", create,info,sid,attr,(attr&sessionHasGraphicAccess)?"true":"false",(attr&sessionHasTTY)?"true":"false",ui,uiCheck,allowed?"true":"false"); fflush(stdout);
  if (create || info || ui || uiCheck || allowed || (attr & (sessionHasGraphicAccess|sessionHasTTY))) return 78;
  pid_t child=fork(); if(child<0)return 71;
  if(child==0) {
    SecuritySessionId childSid=0;SessionAttributeBits childAttr=0;
    OSStatus childInfo=SessionGetInfo(callerSecuritySession,&childSid,&childAttr);
    printf("{\"phase\":\"codesign-child-session\",\"infoStatus\":%d,\"securitySessionID\":%u,\"attributes\":%u,\"pid\":%d}\n",childInfo,childSid,childAttr,getpid());fflush(stdout);
    if(childInfo || childSid!=sid || (childAttr & (sessionHasGraphicAccess|sessionHasTTY))) _exit(78);
    execl("/usr/bin/codesign","codesign","--force","--timestamp","--options","runtime","--sign","CB9A69FB1C87502D47002354EF005A4796DD41F1",argv[1],(char*)NULL);
    _exit(71);
  }
  int status=0;if(waitpid(child,&status,0)!=child)return 71;
  int exitCode=WIFEXITED(status)?WEXITSTATUS(status):128+WTERMSIG(status);
  printf("{\"phase\":\"codesign-terminal\",\"childPID\":%d,\"exitCode\":%d,\"waitpidConfirmed\":true}\n",child,exitCode);return exitCode;
}
