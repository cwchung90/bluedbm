// Copyright (c) 2013 Quanta Research Cambridge, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// bsv libraries
import SpecialFIFOs::*;
import Vector::*;
import StmtFSM::*;
import FIFO::*;

// portz libraries
import CtrlMux::*;
import Portal::*;
import Leds::*;
import ConnectalMemory::*;
import MemTypes::*;
import MemServer::*;
import MMU::*;

import HostInterface::*;

// generated by tool
import FlashRequest::*;
import FlashIndication::*;

// generated by tool: hopefully only this part will change
import MemServerRequest::*;
import MMURequest::*;
import MemServerIndication::*;
import MMUIndication::*;

`ifndef BSIM
import Xilinx       :: *;
import XilinxCells ::*;
import DefaultValue    :: *;
`endif
import Clocks :: *;


// defined by user
import Main::*;
import AuroraCommon::*;
import TopPins::*;
import IfcNames::*;
import ConnectalConfig::*;

//(* synthesize *)
module mkConnectalTop#(Clock clk200, Reset rst200) (ConnectalTop) ;
//module mkConnectalTop (ConnectalTop) ;

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	/////////////////////////////////////////

	FlashIndicationProxy flashIndicationProxy <- mkFlashIndicationProxy(FlashIndicationH2S);

	MainIfc hwmain <- mkMain(flashIndicationProxy.ifc, clk200, rst200);
	FlashRequestWrapper flashRequestWrapper <- mkFlashRequestWrapper(FlashRequestS2H,hwmain.request);
   
	let readClients = hwmain.dmaReadClient;
	let writeClients = hwmain.dmaWriteClient;
   
	Vector#(2,StdPortal) portals;
	portals[0] = flashRequestWrapper.portalIfc;
	portals[1] = flashIndicationProxy.portalIfc; 

	let ctrl_mux <- mkSlaveMux(portals);
   
	Vector#(NumWriteClients,MemWriteClient#(DataBusWidth)) nullWriters = replicate(null_mem_write_client());
	Vector#(NumReadClients,MemReadClient#(DataBusWidth)) nullReaders = replicate(null_mem_read_client());

	interface readers = take(append(readClients, nullReaders));
	interface writers = take(append(writeClients, nullWriters));
	interface interrupt = getInterruptVector(portals);
	interface slave = ctrl_mux;

	interface Top_Pins pins;
		interface aurora_fmc1 = hwmain.aurora_fmc1;
		interface aurora_clk_fmc1 = hwmain.aurora_clk_fmc1;
	endinterface
endmodule


