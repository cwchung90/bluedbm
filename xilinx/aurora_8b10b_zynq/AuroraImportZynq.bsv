package AuroraImportZynq;

import FIFO::*;
import FIFOF::*;
import Clocks :: *;
import DefaultValue :: *;
import Xilinx :: *;
import XilinxCells :: *;
import ConnectalXilinxCells::*;

import AuroraCommon::*;

import AuroraGearbox::*;

interface AuroraIfc;
	method Action send(DataIfc data, PacketType ptype);
	method ActionValue#(Tuple2#(DataIfc, PacketType)) receive;
	method Tuple4#(Bit#(32), Bit#(32), Bit#(32), Bit#(32)) getDebugCnts;

	interface Clock clk;
	interface Reset rst;

	method Bit#(1) channel_up;
	method Bit#(1) lane_up;
	method Bit#(1) hard_err;
	method Bit#(1) soft_err;
	method Bit#(8) data_err_count;
	
	(* prefix = "" *)
	interface Aurora_Pins#(4) aurora;

	method Bit#(16) curSendBudget;
endinterface

(* synthesize *)
module mkAuroraIntra#(Clock gtx_clk_p, Clock gtx_clk_n, Clock clk200) (AuroraIfc);

	Clock cur_clk <- exposeCurrentClock; // assuming 200MHz clock
	Reset cur_rst <- exposeCurrentReset;
	

`ifndef BSIM
	ClockDividerIfc auroraIntraClockDiv4 <- mkDCMClockDivider(4, 5, clocked_by clk200);
	Reset defaultReset <- exposeCurrentReset;
	Clock clk50 = auroraIntraClockDiv4.slowClock;
	Reset rst50 <- mkAsyncReset(2, defaultReset, clk50);

	Clock fmc1_gtx_clk_i <- mkClockIBUFDS_GTE2(
`ifdef ClockDefaultParam
						   defaultValue,
`endif
						   True, gtx_clk_p, gtx_clk_n);

	MakeResetIfc rstgtxifc <- mkReset(16384, True, clk50);
    Reset rstgtx = rstgtxifc.new_rst;
	Reset rstgtx_a <- mkAsyncReset(2, rstgtx, clk50);

	AuroraImportIfc#(4) auroraIntraImport <- mkAuroraImport_8b10b_zynq(fmc1_gtx_clk_i, clk50, rst50, rstgtx);

	Reg#(Bit#(32)) auroraResetCounter <- mkReg(0); //, clocked_by clk50, reset_by rst50ifc.new_rst);
	rule resetAurora;
		if ( auroraResetCounter < 1024*1024*512 ) begin
			auroraResetCounter <= auroraResetCounter +1 ;
			if ( auroraResetCounter < 1024*1024*128 && auroraIntraImport.user.channel_up == 0 ) begin
				rstgtxifc.assertReset;
			end
		end else begin
			auroraResetCounter <= 0;
		end
	endrule
`else
	//Clock gtx_clk = cur_clk;
	AuroraImportIfc#(4) auroraIntraImport <- mkAuroraImport_8b10b_bsim;
`endif


	Clock aclk = auroraIntraImport.aurora_clk;
	Reset arst = auroraIntraImport.aurora_rst;


	Reg#(Bit#(32)) gearboxSendCnt <- mkReg(0);
	Reg#(Bit#(32)) gearboxRecCnt <- mkReg(0);
	Reg#(Bit#(32)) auroraSendCnt <- mkReg(0, clocked_by aclk, reset_by arst);
	Reg#(Bit#(32)) auroraRecCnt <- mkReg(0, clocked_by aclk, reset_by arst);
	Reg#(Bit#(32)) auroraSendCntCC <- mkSyncRegToCC(0, aclk, arst);
	Reg#(Bit#(32)) auroraRecCntCC <- mkSyncRegToCC(0, aclk, arst);
	rule syncCnt;
		auroraSendCntCC <= auroraSendCnt;
		auroraRecCntCC <= auroraRecCnt;
	endrule


	Reg#(Bit#(32)) auroraInitCnt <- mkReg(0, clocked_by aclk, reset_by arst);
`ifndef BSIM
	Integer auroraInitWait = 1024*1024*512;
`else
	Integer auroraInitWait = 512;
`endif

	AuroraGearboxIfc auroraGearbox <- mkAuroraGearbox(aclk, arst);

	rule auroraInit ( auroraInitCnt < fromInteger(auroraInitWait) );
		auroraInitCnt <= auroraInitCnt + 1;
	endrule

	rule auroraOut if (auroraIntraImport.user.channel_up==1 && auroraInitCnt >= fromInteger(auroraInitWait));
		let d <- auroraGearbox.auroraSend;
		//if ( auroraIntraImport.user.channel_up == 1 ) begin
			$display("Gearbox send out: %x", d);
			auroraSendCnt <= auroraSendCnt + 1;
			auroraIntraImport.user.send(d);
		//end
	endrule

	/*
	rule resetDeadLink ( auroraIntraImport.user.channel_up == 0 );
		auroraGearbox.resetLink;
		$display("Gearbox reset link");
	endrule
	*/

	FIFO#(Bit#(AuroraWidth)) auroraRecvQ <- mkSizedFIFO(8, clocked_by aclk, reset_by arst);
	rule auroraR;
		let d <- auroraIntraImport.user.receive;
		Bit#(8) header = truncate(d>>valueOf(BodySz));
		Bit#(1) idx = header[7];
		Bit#(1) control = header[6];
		if ( auroraInitCnt >= fromInteger(auroraInitWait) || control == 1 ) begin
			auroraRecvQ.enq(d);
		end
	endrule

	rule auroraIn( auroraInitCnt >= fromInteger(auroraInitWait));
		let d = auroraRecvQ.first;
		auroraRecvQ.deq;

		$display("Gearbox received: %x", d);
		auroraRecCnt <= auroraRecCnt + 1;
		auroraGearbox.auroraRecv(d);
	endrule

	ReadOnly#(Bit#(16)) aSendB <- mkNullCrossingWire(noClock, auroraGearbox.curSendBudget);

	method Tuple4#(Bit#(32), Bit#(32), Bit#(32), Bit#(32)) getDebugCnts;
		return tuple4(gearboxSendCnt, gearboxRecCnt, auroraSendCntCC, auroraRecCntCC);
	endmethod

	method Action send(DataIfc data, PacketType ptype);
		auroraGearbox.send(data, ptype);
		gearboxSendCnt <= gearboxSendCnt + 1;
	endmethod

	method ActionValue#(Tuple2#(DataIfc, PacketType)) receive;
		let d <- auroraGearbox.recv;
		gearboxRecCnt <= gearboxRecCnt + 1;
		return d;
	endmethod

	method channel_up = auroraIntraImport.user.channel_up;
	method lane_up = auroraIntraImport.user.lane_up;
	method hard_err = auroraIntraImport.user.hard_err;
	method soft_err = auroraIntraImport.user.soft_err;
	method data_err_count = auroraIntraImport.user.data_err_count;

	interface Clock clk = auroraIntraImport.aurora_clk;
	interface Reset rst = auroraIntraImport.aurora_rst;

	interface Aurora_Pins aurora = auroraIntraImport.aurora;
	method Bit#(16) curSendBudget;
		return aSendB;
	endmethod
endmodule

module mkAuroraImport_8b10b_bsim (AuroraImportIfc#(4));
	Clock clk <- exposeCurrentClock;
	Reset rst <- exposeCurrentReset;

	FIFOF#(Bit#(128)) mirrorQ <- mkSizedFIFOF(2);
	Reg#(Bit#(1)) laneUpR <- mkReg(0);
	Reg#(Bit#(32)) laneUpDelay <- mkReg(500);

	rule updateLaneUp;
		if (laneUpDelay ==0) begin
			laneUpR <= 1;
		end
		else begin
			laneUpDelay <= laneUpDelay - 1;
		end
	endrule


	rule detectFull if (!mirrorQ.notFull);
		$display("WARNING: mirrorQ is full!");
	endrule

	interface aurora_clk = clk;
	interface aurora_rst = rst;
	interface AuroraControllerIfc user;
		interface Reset aurora_rst_n = rst;

		method Bit#(1) channel_up;
			return laneUpR; 
		endmethod
		method Bit#(1) lane_up;
			return laneUpR;
		endmethod
		method Bit#(1) hard_err;
			return 0;
		endmethod
		method Bit#(1) soft_err;
			return 0;
		endmethod
		method Bit#(8) data_err_count;
			return 0;
		endmethod

		method Action send(Bit#(128) data);
			mirrorQ.enq(data);
		endmethod
		method ActionValue#(Bit#(128)) receive;
			mirrorQ.deq;
			return mirrorQ.first;
		endmethod
	endinterface
endmodule

import "BVI" aurora_8b10b_zynq_exdes =
module mkAuroraImport_8b10b_zynq#(Clock gtx_clk_in, Clock init_clk, Reset init_rst_n, Reset gt_rst_n) (AuroraImportIfc#(4));
	default_clock no_clock;
	default_reset no_reset;

	input_clock (INIT_CLK_IN) = init_clk;
	input_reset (RESET_N) = init_rst_n;
	input_reset (GT_RESET_N) = gt_rst_n;

	output_clock aurora_clk(USER_CLK);
	output_reset aurora_rst(USER_RST_N) clocked_by (aurora_clk);

	input_clock (GTX_CLK) = gtx_clk_in;

	interface Aurora_Pins aurora;
		method rxn_in(RXN) enable((*inhigh*) rx_n_en) reset_by(no_reset) clocked_by(gtx_clk_in);
		method rxp_in(RXP) enable((*inhigh*) rx_p_en) reset_by(no_reset) clocked_by(gtx_clk_in);
		method TXN txn_out() reset_by(no_reset) clocked_by(gtx_clk_in); 
		method TXP txp_out() reset_by(no_reset) clocked_by(gtx_clk_in);
	endinterface

	interface AuroraControllerIfc user;
		output_reset aurora_rst_n(USER_RST) clocked_by (aurora_clk);

		method CHANNEL_UP channel_up;
		method LANE_UP lane_up;
		method HARD_ERR hard_err;
		method SOFT_ERR soft_err;
		method ERR_COUNT data_err_count;

		method send(TX_DATA) enable(tx_en) ready(tx_rdy) clocked_by(aurora_clk) reset_by(aurora_rst);
		method RX_DATA receive() enable((*inhigh*) rx_en) ready(rx_rdy) clocked_by(aurora_clk) reset_by(aurora_rst);
	endinterface
	
	schedule (aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_channel_up, user_lane_up, user_hard_err, user_soft_err, user_data_err_count) CF 
	(aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_channel_up, user_lane_up, user_hard_err, user_soft_err, user_data_err_count);
	schedule (user_send) CF (aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_channel_up, user_lane_up, user_hard_err, user_soft_err, user_data_err_count);

	schedule (user_receive) CF (aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_channel_up, user_lane_up, user_hard_err, user_soft_err, user_data_err_count);

	schedule (user_receive) SB (user_send);
	schedule (user_send) C (user_send);
	schedule (user_receive) C (user_receive);

endmodule

endpackage: AuroraImportZynq
