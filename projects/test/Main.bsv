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

import FIFOF::*;
import FIFO::*;
import BRAMFIFO::*;
import BRAM::*;
import GetPut::*;
import ClientServer::*;

import Vector::*;

import PortalMemory::*;
import MemTypes::*;
import MemreadEngine::*;
import MemwriteEngine::*;
import Pipe::*;

import AuroraImportFmc1::*;
import AuroraExtImport::*;
import AuroraCommon::*;

import PageCache::*;
import DMABurstHelper::*;


//typedef TAdd#(8192,128) PageBytes;
typedef 16 WordBytes;
typedef TMul#(8,WordBytes) WordSz;

interface StorageBridgeRequest;
	method Action addBridgeBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);
endinterface

interface StorageBridgeIndication;
	method Action writePage(Bit#(32) pageIdx, Bit#(32) bufidx);
endinterface

interface FlashRequest;
	method Action readPage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) bufidx);
	method Action writePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) bufidx);
	method Action erasePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block);
	method Action sendTest(Bit#(32) data);
	method Action addWriteHostBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);
	method Action addReadHostBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);

	method Action start(Bit#(32) dummy);
endinterface

interface FlashIndication;
	method Action readDone(Bit#(32) rbuf);
	method Action writeDone(Bit#(32) tag);
	method Action reqFlashCmd(Bit#(32) inq, Bit#(32) count);
	method Action hexDump(Bit#(32) data);
endinterface

interface MainIfc;
	interface FlashRequest request;
	interface StorageBridgeRequest bridgeRequest;
	interface Vector#(NumDmaChannels, ObjectReadClient#(WordSz)) dmaReadClient;
	interface Vector#(NumDmaChannels, ObjectWriteClient#(WordSz)) dmaWriteClient;
	//interface ObjectReadClient#(WordSz) dmaReadClient;
	//interface ObjectWriteClient#(WordSz) dmaWriteClient;

	interface Aurora_Pins#(4) aurora_fmc1;
	interface Aurora_Clock_Pins aurora_clk_fmc1;

	interface Vector#(AuroraExtCount, Aurora_Pins#(1)) aurora_ext;
	interface Aurora_Clock_Pins aurora_quad119;
endinterface

typedef enum {Read,Write,Erase} CmdType deriving (Bits,Eq);
typedef struct { Bit#(5) channel; Bit#(5) chip; Bit#(8) block; Bit#(8) page; CmdType cmd; Bit#(8) tag; Bit#(8) bufidx;} FlashCmd deriving (Bits,Eq);

module mkMain#(FlashIndication indication, StorageBridgeIndication bridge_indication
	, Clock clk250, Reset rst250)(MainIfc);
	
	Integer pageBytes = valueOf(PageBytes);
	Integer wordBytes = valueOf(WordBytes); 
	Integer pageWords = pageBytes/wordBytes;

	Integer numDmaChannels = valueOf(NumDmaChannels);

	Reg#(Bool) started <- mkReg(False);

	GtxClockImportIfc gtx_clk_fmc1 <- mkGtxClockImport;
	AuroraIfc auroraIntra1 <- mkAuroraIntra(gtx_clk_fmc1.gtx_clk_p_ifc, gtx_clk_fmc1.gtx_clk_n_ifc, clk250);
	/*
   
	Reg#(Bit#(32)) auroraTestIdx <- mkReg(0);
	rule sendAuroraTest(auroraTestIdx > 0);
		auroraIntra1.send(zeroExtend(auroraTestIdx), 7);
		
		auroraTestIdx <= auroraTestIdx - 1;
	endrule
	FIFO#(Bit#(32)) dataQ <- mkSizedFIFO(32);
	rule recvTestData;
		let datao <- auroraIntra1.receive;
		let data = tpl_1(datao);
		let ptype = tpl_2(datao);

		dataQ.enq({2'b0,ptype,data[23:0]});
	endrule

	Reg#(Bit#(32)) auroraDataCheck <- mkReg(0);
	rule dumpD;
		dataQ.deq;
		let data = dataQ.first;
		auroraDataCheck <= data;

		if ( auroraDataCheck - 1 != data )
			indication.hexDump(truncate(data));
		else if ( data[15:0] == 0 ) 
			indication.hexDump(truncate(data));
	endrule
*/
	GtxClockImportIfc gtx_clk_119 <- mkGtxClockImport;
	AuroraExtIfc auroraExt <- mkAuroraExt(gtx_clk_119.gtx_clk_p_ifc, gtx_clk_119.gtx_clk_n_ifc, clk250);
	Reg#(Bit#(32)) auroraTestIdx <- mkReg(0);
	rule sendAuroraTest(auroraTestIdx > 0);
		auroraExt.user[1].send({1,auroraTestIdx[30:0]});
		auroraExt.user[3].send({0,auroraTestIdx[30:0]});
		
		auroraTestIdx <= auroraTestIdx - 1;
	endrule
	FIFO#(Bit#(32)) dataQ <- mkSizedFIFO(32);
	rule recvTestData;
		let data <- auroraExt.user[0].receive;

		dataQ.enq(truncate(data));
	endrule
	
	rule recvTestData3;
		let data <- auroraExt.user[2].receive;

		dataQ.enq(truncate(data));
	endrule

	Reg#(Bit#(32)) auroraDataCheck <- mkReg(0);
	rule dumpD;
		dataQ.deq;
		let data = dataQ.first;
		auroraDataCheck <= data;

/*
		if ( auroraDataCheck - 1 != data )
			indication.hexDump(truncate(data));
		else */
		if ( data[17:0] == 0 ) 
			indication.hexDump(truncate(data));
	endrule

	Vector#(NumDmaChannels, PageCacheIfc#(2,128)) pageCaches; // FIXME WriteTagCount no longer total number of tags //changed to 128
	for ( Integer wIdx = 0; wIdx < numDmaChannels; wIdx = wIdx + 1 ) begin
		let pageCache <- mkPageCache; 
		pageCaches[wIdx] = pageCache;
	end

/////////////// DMA Writer with page cache //////////////////////////////////////
	Vector#(NumDmaChannels, DMAWriteEngineIfc#(WordSz)) dmaWriters;
	Vector#(NumDmaChannels, FreeBufferClientIfc) dmaWriterFreeBufferClient;
	//MemwriteEngineV#(WordSz,1,NumDmaChannels) we <- mkMemwriteEngine;
	Vector#(NumDmaChannels, MemwriteEngine#(WordSz,1)) weV <- replicateM(mkMemwriteEngine);
	for ( Integer wIdx = 0; wIdx < numDmaChannels; wIdx = wIdx + 1 ) begin
		let pageCache = pageCaches[wIdx];

		let we = weV[wIdx];

		//DMAWriteEngineIfc#(WordSz) dmaWriter <- mkDmaWriteEngine(we.writeServers[wIdx], we.dataPipes[wIdx]);
		DMAWriteEngineIfc#(WordSz) dmaWriter <- mkDmaWriteEngine(we.writeServers[0], we.dataPipes[0]);
		dmaWriters[wIdx] = dmaWriter;

		rule dmaWriteData;
			let r <- pageCache.readWord;
			let d = tpl_1(r);
			let t = tpl_2(r);
			//$display ( "reading from pagecache %x %d @ %d", d, t, wIdx );
			dmaWriter.write(d,t);
		endrule

		dmaWriterFreeBufferClient[wIdx] = dmaWriter.bufClient;
	end
	FreeBufferManagerIfc writeBufMan <- mkFreeBufferManager(dmaWriterFreeBufferClient);

	//Reg#(Bit#(4)) readDoneCounter <- mkReg(0);
	//Reg#(Bit#(32)) rbufBuff <- mkReg(0);
	//Reg#(Bit#(32)) tagBuff <- mkReg(0);
	//FIXME done's don't always come in 4s!
	rule dmaWriteDoneCheck;
			let r <- writeBufMan.done;
			/*
			let rbuf = tpl_1(r);
			let tag = tpl_2(r);
			*/
			indication.readDone(zeroExtend(r));

/*
		if ( readDoneCounter >= 4 ) begin
			readDoneCounter <= 0;
		end
		else begin
			$display( "read done tag %d buf %d", tag, rbuf );

			rbufBuff <= (rbufBuff<<8) + zeroExtend(rbuf);
			tagBuff <= (tagBuff<<8) + zeroExtend(tag);
			readDoneCounter <= readDoneCounter + 1;
		end
*/
	endrule
/////////////////////////////////////////////////////////////////////////////////////

	FIFO#(Bool) dmaReadThrottleQ <- mkSizedFIFO(1);

	Vector#(NumDmaChannels, DMAReadEngineIfc#(WordSz)) dmaReaders;
	//MemreadEngineV#(WordSz,1, NumDmaChannels)  re <- mkMemreadEngine;
	Vector#(NumDmaChannels, MemreadEngine#(WordSz,2))  reV <- replicateM(mkMemreadEngine);
	FIFO#(Bit#(8)) dmaReadDoneQ <- mkFIFO;
	rule driveDmaReadDone;
		let bufidx = dmaReadDoneQ.first;
		dmaReadDoneQ.deq;
		indication.writeDone(zeroExtend(bufidx));

		dmaReadThrottleQ.deq;
	endrule

	for ( Integer rIdx = 0; rIdx < numDmaChannels; rIdx = rIdx + 1 ) begin
		let pageCache = pageCaches[rIdx];
		let re = reV[rIdx];

		DMAReadEngineIfc#(WordSz) dmaReader <- mkDmaReadEngine(re.readServers[0], re.dataPipes[0]);
		//DMAReadEngineIfc#(WordSz) dmaReader <- mkDmaReadEngine(re.readServers[rIdx], re.dataPipes[rIdx]);
		dmaReaders[rIdx] = dmaReader;

		rule dmaReadDone;
			let bufidx <- dmaReader.done;
			dmaReadDoneQ.enq(bufidx);
		endrule
		rule dmaReadData;
			let r <- dmaReader.read;
			let d = tpl_1(r);
			let t = tpl_2(r);
			pageCache.writeWord(d,t);
			//$display( "writing to pagecache %x %d", d, t );
		endrule
	end // for loop



	Reg#(Bit#(32)) curReqsInQ <- mkReg(0);
	Reg#(Bit#(32)) numReqsRequested <- mkReg(0);
	rule driveNewReqs(started&& curReqsInQ + numReqsRequested < 128-48 );
		numReqsRequested <= numReqsRequested + 32;
		indication.reqFlashCmd(curReqsInQ, 32);
		//$display( "Requesting more flash commands" );
	endrule

	FIFO#(FlashCmd) flashCmdQ <- mkSizedFIFO(128);
	rule driveFlashCmd (started);
		let cmd = flashCmdQ.first;
		
		if ( cmd.cmd == Read ) begin
			curReqsInQ <= curReqsInQ -1;

			flashCmdQ.deq;

			// temporary stuff
			let dmaWriter = dmaWriters[cmd.channel];
			let pageCache = pageCaches[cmd.channel];

			dmaWriter.startWrite(cmd.bufidx, fromInteger(pageWords));

			pageCache.readPage( zeroExtend(cmd.page), cmd.bufidx);
			$display( "starting page read %d at tag %d in buffer %d", cmd.page, cmd.tag, cmd.bufidx );
		end else if ( cmd.cmd == Write ) begin
			curReqsInQ <= curReqsInQ -1;

			flashCmdQ.deq;

			let dmaReader = dmaReaders[cmd.channel];
			let pageCache = pageCaches[cmd.channel];

			dmaReader.startRead(cmd.bufidx, fromInteger(pageWords));

			pageCache.writePage(zeroExtend(cmd.page), cmd.bufidx);
			bridge_indication.writePage(zeroExtend(cmd.page), zeroExtend(cmd.bufidx));
			$display( "starting page write page %d at tag %d", cmd.page, cmd.bufidx );

			dmaReadThrottleQ.enq(True);
		end
	endrule

   
	Vector#(NumDmaChannels, ObjectReadClient#(WordSz)) dmaReadClients;
	Vector#(NumDmaChannels, ObjectWriteClient#(WordSz)) dmaWriteClients;
	for ( Integer idx = 0; idx < numDmaChannels; idx = idx + 1 ) begin
		dmaReadClients[idx] = reV[idx].dmaClient;
		dmaWriteClients[idx] = weV[idx].dmaClient;
	end

   interface FlashRequest request;
	method Action readPage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) bufidx);

		CmdType cmd = Read;
		FlashCmd fcmd = FlashCmd{
			channel: truncate(channel),
			chip: truncate(chip),
			block: truncate(block),
			page: truncate(page),
			cmd: cmd,
			bufidx: truncate(bufidx),
			tag: ?};

		flashCmdQ.enq(fcmd);
		curReqsInQ <= curReqsInQ +1;
		numReqsRequested <= numReqsRequested - 1;

			
	endmethod
   method Action writePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) bufidx);
		CmdType cmd = Write;
		FlashCmd fcmd = FlashCmd{
			channel: truncate(channel),
			chip: truncate(chip),
			block: truncate(block),
			page: truncate(page),
			cmd: cmd,
			bufidx: truncate(bufidx),
			tag: ?};

		flashCmdQ.enq(fcmd);
		curReqsInQ <= curReqsInQ +1;
		numReqsRequested <= numReqsRequested - 1;
	endmethod
	method Action erasePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block);
		CmdType cmd = Erase;
		FlashCmd fcmd = FlashCmd{
			channel: truncate(channel),
			chip: truncate(chip),
			block: truncate(block),
			page: 0,
			cmd: cmd,
			tag: 0};

		flashCmdQ.enq(fcmd);
		curReqsInQ <= curReqsInQ +1;
		numReqsRequested <= numReqsRequested - 1;
	endmethod
	method Action sendTest(Bit#(32) data);
		auroraTestIdx <= data;
	endmethod
	method Action addWriteHostBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);
		for (Integer i = 0; i < numDmaChannels; i = i + 1) begin
			dmaReaders[i].addBuffer(truncate(idx), offset, pointer);
		end
	endmethod
	method Action addReadHostBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);
		writeBufMan.addBuffer(truncate(offset), pointer);
	endmethod
	method Action start(Bit#(32) dummy);
		indication.hexDump({8'hcc,0,
			auroraExt.user[0].lane_up,
			auroraExt.user[0].channel_up,
			auroraExt.user[1].lane_up,
			auroraExt.user[1].channel_up,
			auroraExt.user[2].lane_up,
			auroraExt.user[2].channel_up,
			auroraExt.user[3].lane_up,
			auroraExt.user[3].channel_up
			});
		started <= True;
	endmethod
	endinterface

	interface StorageBridgeRequest bridgeRequest;
		method Action addBridgeBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);
		endmethod
	endinterface

   //interface ObjectReadClient dmaReadClient = re.dmaClient;
   //interface ObjectWriteClient dmaWriteClient = we.dmaClient;
   interface ObjectReadClient dmaReadClient = dmaReadClients;
   interface ObjectWriteClient dmaWriteClient = dmaWriteClients;

   interface Aurora_Pins aurora_fmc1 = auroraIntra1.aurora;
   interface Aurora_Clock_Pins aurora_clk_fmc1 = gtx_clk_fmc1.aurora_clk;

	interface Aurora_Pins aurora_ext = auroraExt.aurora;
	interface Aurora_Clock_Pins aurora_quad119 = gtx_clk_119.aurora_clk;
endmodule
