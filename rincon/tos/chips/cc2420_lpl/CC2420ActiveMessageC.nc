/*
 * Copyright (c) 2005-2006 Rincon Research Corporation
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 * - Neither the name of the Rincon Research Corporation nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE
 * ARCHED ROCK OR ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE
 */

/**
 * The Active Message layer for the CC2420 radio. This configuration
 * just layers the AM dispatch (CC2420ActiveMessageM) on top of the
 * underlying CC2420 radio packet (CC2420CsmaCsmaCC), which is
 * inherently an AM packet (acknowledgements based on AM destination
 * addr and group). Note that snooping may not work, due to CC2420
 * early packet rejection if acknowledgements are enabled.
 *
 * @author Philip Levis
 * @author David Moss
 */

#include "CC2420.h"

configuration CC2420ActiveMessageC {
  provides {
    interface SplitControl;
    interface AMSend[am_id_t id];
    interface Receive[am_id_t id];
    interface Receive as Snoop[am_id_t id];
    interface AMPacket;
    interface Packet;
    interface CC2420Packet;
    interface PacketAcknowledgements;
    interface RadioBackoff[am_id_t amId];
    interface LowPowerListening;
    interface MessageTransport;
  }
}
implementation {

  components CC2420ActiveMessageP as AM;
  components CC2420CsmaC as CsmaC;
  components ActiveMessageAddressC as Address;
  components UniqueSendC;
  components UniqueReceiveC;
  components CC2420PacketC;
  
#ifdef LOW_POWER_LISTENING
  components CC2420LowPowerListeningC as LplC;
#else
  components CC2420LplDummyC as LplC;
#endif

#ifdef MESSAGE_TRANSPORT
  components MessageTransportC as TransportC;
#else
  components MessageTransportDummyC as TransportC;
#endif

  
  RadioBackoff = CsmaC;
  Packet       = AM;
  AMSend   = AM;
  Receive  = AM.Receive;
  Snoop    = AM.Snoop;
  AMPacket = AM;
  MessageTransport = TransportC;
  LowPowerListening = LplC;
  CC2420Packet = CC2420PacketC;
  PacketAcknowledgements = CC2420PacketC;
  
  
  // SplitControl Layers
  SplitControl = LplC;
  LplC.SubControl -> CsmaC;
  
  // Send Layers
  AM.SubSend -> UniqueSendC;
  UniqueSendC.SubSend -> TransportC;
  TransportC.SubSend -> LplC.Send;
  LplC.SubSend -> CsmaC;
  
  // Receive Layers
  AM.SubReceive -> LplC;
  LplC.SubReceive -> UniqueReceiveC;
  UniqueReceiveC.SubReceive -> CsmaC;

  AM.amAddress -> Address;
  AM.CC2420Packet -> CC2420PacketC;
  
}