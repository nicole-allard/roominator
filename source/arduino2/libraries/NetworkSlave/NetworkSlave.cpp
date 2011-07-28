#include "NetworkSlave.cpp"
#include "WProgram.h"
#include "Wire.h"

#define UPSTREAM_MESSAGE_SIZE 2

NetworkSlave::NetworkSlave() {
  ud.setCancel(false);
  ud.setReserve(0);
  dd.setCurrentReservations(false);
  dd.setPendingReservations(false);
  dd.setDisplayString(NULL);
}

char* NetworkSlave::getUpstreamData() {
  char message[UPSTREAM_MESSAGE_SIZE];
  char reserve[1];
  message[0] = (char) ud.getCancel();
  sprintf(reserve, "%u", ud.getReserve());
  message[1] = (char) reserve;
  free(message);
  return &message;
}

void NetworkSlave::setDownstreamData(char *received) {
  dd = DownstreamDataParser::parseDownstreamData(received);
}

void NetworkSlave::reserve() {
  ud.setCancel(false);
  ud.setReserve(ud.getReserve()+1);
}

void NetworkSlave::cancel() {
  if (dd.getCurrentReservation()) {
    ud.setReserve(0);
    ud.setCancel(true);
  }
}
