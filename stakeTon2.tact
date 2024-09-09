import "@stdlib/deploy";
import "@stdlib/ownable";

message MsgStake {
    amount: Int as coins;
    info: Slice as remaining;
}

message MsgSubStake {
    amount: Int as coins;
    stakeTime:Int as uint32;
    minEndTime: Int as uint32;
    info: Slice as remaining;
}
message MsgWithdrawBack {
    amount: Int as coins;
    fromAddr:Address;
}
message MsgSubWithdraw {
    fromAddr:Address;
}
message MsgSetStart {
    bStart:Int as uint32;
    startTime:Int as uint32;
    endTime:Int as uint32;
}
message MsgSysSet {
    bPause:Bool;
    bAllowUserWithdraw:Bool;
}
message MsgGasSet {
    minTonForStorage: Int as coins;
    gasConsumption: Int as coins;
}
message MsgGasSetSub {
    addr: Address;
    minTonForStorage: Int as coins;
    gasConsumption: Int as coins;
}
struct StakeData {
    sumNum: Int as uint64;
    sumStakeAmount: Int as coins;
    lastStakeAmount: Int as coins;
    minStakeTime: Int as uint32;
    bStart:Bool;
    startTime:Int as uint32;
    endTime:Int as uint32;
    bPause:Bool = false;
    minTonForStorage: Int as coins;
    gasConsumption: Int as coins;
}

message MsgStakeAddrWidthdwaw {
    addr: Address;
}
message MsgSubStakeAddrWidthdwaw {
    addr: Address;
}
message MsgStakeAddrDel {
    addr: Address;
}
message MsgSubStakeAddrDel {
    addr: Address;
}

contract StakeContract with Deployable, OwnableTransferable {
    defId: Int ;
    owner: Address; 
    minTonForStorage: Int = ton("0.02"); // enough for 1 KB of storage for 2.5 years
    gasConsumption: Int = ton("0.02");
    const minStakeTime: Int = 30*24*3600;
    sumNum: Int as uint64 =0;
    sumStakeAmount: Int as coins =0;
    lastStakeAmount: Int as coins =0;
    
    bStart:Bool = false;
    startTime:Int as uint32 = 0;
    endTime:Int as uint32 = 1920666344;
    bPause:Bool = false;

    init() {
        self.defId = 2;
        self.owner = sender();
        self.rebackTon(sender());
    }

    receive() {
    }

    //read
    get fun balance(): Int {
        return myBalance(); 
    }
    get fun timeNow(): Int {
        return now(); 
    }
    get fun getstakeSubContractAddressInit(address: Address): StateInit {
        return initOf StakeSubContract(address, myAddress());
    }
    get fun getstakeSubContractAddress(owner: Address): Address {
        return contractAddress(initOf StakeSubContract(owner, myAddress()));
    }
    get fun getStakeData(): StakeData {//addr: Address
        return StakeData{
            sumNum: self.sumNum,
            sumStakeAmount: self.sumStakeAmount,
            lastStakeAmount: self.lastStakeAmount,
            minStakeTime: self.minStakeTime,
            bStart:self.bStart,
            startTime:self.startTime,
            endTime:self.endTime,
            bPause:self.bPause,
            minTonForStorage:self.minTonForStorage,
            gasConsumption:self.gasConsumption,
        };
    }
    fun msg_value(value: Int): Int {
        let msgVal: Int = value;
        let ton_balance_before_msg: Int = myBalance() - msgVal;
        let storage_fee: Int = self.minTonForStorage - min(ton_balance_before_msg, self.minTonForStorage);
        msgVal = msgVal - (storage_fee + self.gasConsumption);
        return msgVal;
    }
    fun rebackTon(addr: Address){
        let ctx: Context = context();
        let reVal: Int = self.msg_value(ctx.value);  
        if(reVal>0){
            send(SendParameters{
                to: addr,
                value: reVal,
                mode:  0 |  SendIgnoreErrors,
                bounce: false,
                body: "Deploy done".asComment()
            });
        }
    }
    //write
    receive(msg: MsgStake) {
        let ctx: Context = context();
        require(self.bStart, "need start");
        require(!self.bPause, "paused");
        require(self.startTime<now(), "need start");
        require(self.endTime>now(), "already end");
        require(msg.amount >= ton("0.1"), "not enough value");

        let fwd_fee: Int = ctx.readForwardFee();
        let reVal = ctx.value-msg.amount-fwd_fee - self.gasConsumption*2 -self.minTonForStorage*2;
        require(reVal > 0, "not enough ton");

        reVal = self.msg_value(ctx.value);  
        require(reVal > 0, "not enough gas");

        self.sumNum += 1;
        self.sumStakeAmount = self.sumStakeAmount + msg.amount;
        self.lastStakeAmount = self.lastStakeAmount + msg.amount;

        let winit: StateInit = self.getstakeSubContractAddressInit(sender());
        send(SendParameters{
            to: contractAddress(winit), 
            value: 0, 
            bounce: true,
            mode: SendRemainingValue,
            body: MsgSubStake{ 
                amount: msg.amount,
                stakeTime: now(),
                minEndTime: now() + self.minStakeTime,
                info: msg.info
            }.toCell(),
            code: winit.code,
            data: winit.data
        });
        emit("MsgStake".asComment());
    }
    bounced(msg: bounced<MsgSubStake>) {
        let ctx: Context = context();
        self.sumNum -= 1;
        self.sumStakeAmount = self.sumStakeAmount - msg.amount;
        self.lastStakeAmount = self.lastStakeAmount - msg.amount;

        send(SendParameters{
            to: sender(),
            value: 0,
            mode:  SendRemainingValue,
            bounce: false,
            body: "MsgSubReBack".asComment()
        });
    }
    receive("MsgWithdraw") {
        let ctx: Context = context();
        require(!self.bPause, "paused");

        let fwd_fee: Int = ctx.readForwardFee();
        let reVal = ctx.value - fwd_fee - self.gasConsumption*3 -self.minTonForStorage*3;
        require(reVal > 0, "not enough gas");

        let winit: StateInit = self.getstakeSubContractAddressInit(sender());
        send(SendParameters{
            to: contractAddress(winit), 
            value: 0, 
            bounce: true,
            mode: SendRemainingValue,
            body: MsgSubWithdraw{ 
                fromAddr: sender()
            }.toCell(),
            code: winit.code,
            data: winit.data
        });
        emit("MsgWithdraw".asComment());
    }
    bounced(msg: bounced<MsgSubWithdraw>) {
        send(SendParameters{
            to: sender(),
            value: 0,
            mode:  SendRemainingValue,
            bounce: false,
            body: "MsgSubReBack".asComment()
        });
    }
    receive(msg: MsgWithdrawBack) {
        let ctx: Context = context();
        let winit: StateInit = self.getstakeSubContractAddressInit(msg.fromAddr);
        require(sender() == contractAddress(winit), "Invalid sender!");

        self.lastStakeAmount = self.lastStakeAmount - msg.amount;

        send(SendParameters{
            to: msg.fromAddr,
            value: 0,
            mode:  SendRemainingValue,
            bounce: false,
            body: "MsgWithdrawBack done".asComment()
        });

        emit("MsgWithdrawBack".asComment());
    }

    //owner
    receive(msg: MsgSetStart) {
        self.requireOwner();
        if(msg.bStart==1){
            self.bStart=true;
        }
        else{
            self.bStart = false;
        }
        self.startTime = msg.startTime;
        self.endTime = msg.endTime;
        self.rebackTon(sender());
    }
    receive(msg: MsgGasSet) {
        self.requireOwner();
        self.minTonForStorage = msg.minTonForStorage;
        self.gasConsumption = msg.gasConsumption;
        self.rebackTon(sender());
    }
    receive(msg: MsgGasSetSub) {
        self.requireOwner();
        send(SendParameters{
            to: msg.addr,
            bounce: false,
            value: 0,
            mode: SendRemainingValue,
            body: MsgGasSetSub{ 
                addr: sender(),
                minTonForStorage: msg.minTonForStorage,
                gasConsumption: msg.gasConsumption,
            }.toCell(),
        });
    }

    receive(msg: MsgStakeAddrWidthdwaw) {
        self.requireOwner();
        send(SendParameters{
            to: msg.addr, 
            bounce: false,
            value: 0,
            mode: SendRemainingValue,
            body: MsgSubStakeAddrWidthdwaw{ 
                addr: sender()
            }.toCell(),
        });
    }
    receive(msg: MsgStakeAddrDel) {
        self.requireOwner();
        send(SendParameters{
            to: msg.addr, 
            bounce: false,
            value: 0,
            mode: SendRemainingValue,
            body: MsgSubStakeAddrDel{ 
                addr: sender()
            }.toCell(),
        });
    }
    receive("delThis") {
        self.requireOwner();
        require(self.lastStakeAmount <=0, "not end!");
        send(SendParameters{
            to: sender(),
            bounce: false,
            value: 0,
            mode: SendRemainingBalance + SendIgnoreErrors
        });
    }

}


struct StakeDataAddress {
    stakeAddress: Address;
    owner: Address;
    amount: Int as coins;
    stakeTime: Int as uint32;
    minEndTime: Int as uint32;
    bStake:Bool;
    bExit:Bool;
    minTonForStorage: Int as coins;
    gasConsumption: Int as coins;
    info: Slice as remaining;
}

contract StakeSubContract {
    minTonForStorage: Int = ton("0.02");
    gasConsumption: Int = ton("0.02");

    amount: Int as coins = 0;
    owner: Address;
    master: Address;
    stakeTime:Int as uint32 = 0;
    minEndTime: Int as uint32 = 0;
    bStake:Bool = false;
    bExit:Bool = false;
    info: Slice as remaining;

    init(owner: Address, master: Address) {
        self.owner = owner;
        self.master = master;
        self.info = emptySlice();
    }
    //read
    receive() {
    }
    get fun balance(): Int {
        return myBalance(); 
    }
    get fun getStakeDataAddress(): StakeDataAddress {
           return StakeDataAddress{
            stakeAddress: myAddress(),
            owner: self.owner,
            amount: self.amount,
            stakeTime: self.stakeTime,
            minEndTime: self.minEndTime,
            bStake:self.bStake,
            bExit:self.bExit,
            minTonForStorage:self.minTonForStorage,
            gasConsumption:self.gasConsumption,
            info:self.info
        };
    }
    fun msg_value(value: Int): Int {
        let msgVal: Int = value;
        let ton_balance_before_msg: Int = myBalance() - msgVal;
        let storage_fee: Int = self.minTonForStorage - min(ton_balance_before_msg, self.minTonForStorage);
        msgVal = msgVal - (storage_fee + self.gasConsumption);
        return msgVal;
    }
    fun msg_valueAmount(value: Int): Int {
        let msg_value: Int = value;
        let ton_balance_before_msg: Int = myBalance() - msg_value - self.amount;
        let storage_fee: Int = self.minTonForStorage - min(ton_balance_before_msg, self.minTonForStorage);
        msg_value = msg_value - (storage_fee + self.gasConsumption);
        return msg_value;
    }
    //master contract write
    receive(msg: MsgSubStake) {
        let ctx: Context = context();
        require(!self.bStake, "already stake");
        require(ctx.sender == self.master, "Invalid sender!");

        let reVal: Int = self.msg_value(ctx.value)-msg.amount;  
        require(reVal > 0, "not enough gton");

        self.amount = msg.amount;
        self.bStake = true;
        self.stakeTime = msg.stakeTime;
        self.minEndTime = msg.minEndTime;
        self.info = msg.info;

        send(SendParameters{
                to: self.owner,
                value: reVal,
                mode: 0 | SendIgnoreErrors,
                bounce: false,
                body: "MsgSubStake done".asComment()
        });

        emit("MsgSubStake".asComment());
    }
    receive("MsgSubReBack") {
        dump("MsgSubReBack");
        send(SendParameters{
                to: self.owner,
                value:0,
                mode: SendRemainingValue | SendIgnoreErrors,
                bounce: false,
                body: "MsgSubReBack done".asComment()
        });
    }
    receive(msg: MsgSubWithdraw) {
        let ctx: Context = context();
        require(ctx.sender == self.master, "Invalid sender!");
        require(self.amount > 0, "need stake");
        require(self.bStake , "need stake");
        require(!self.bExit , "already withdraw");
        require(now()>self.minEndTime, "need wait");

        self.bExit=true;
        let amount = self.amount;
        let fwd_fee: Int = ctx.readForwardFee(); // Gas checks
        let reVal = ctx.value -self.minTonForStorage*2-self.gasConsumption*2;
        require(reVal > 0, "Invalid value");

        reVal = self.msg_valueAmount(ctx.value);  
        require(reVal > self.minTonForStorage + self.gasConsumption, "Invalid value2");
        send(SendParameters{
            to: self.master, 
            value: reVal, 
            bounce: false,
            mode: 0 | SendIgnoreErrors,
            body: MsgWithdrawBack{ 
                amount: amount,
                fromAddr:self.owner
            }.toCell()
        });

        require(myBalance() - ctx.value  - self.minTonForStorage > self.gasConsumption, "Invalid value3");
        send(SendParameters{
                to: self.owner, 
                value:myBalance() - ctx.value  - self.minTonForStorage- self.gasConsumption,
                mode: SendPayGasSeparately | SendIgnoreErrors,
                bounce: false,
                body: "withdraw done".asComment()
            });
        emit("MsgSubWithdraw".asComment());
        return;
    }
    receive(msg: MsgGasSetSub) {
        let ctx: Context = context();
        require(ctx.sender == self.master, "Invalid sender!");

        self.minTonForStorage = msg.minTonForStorage;
        self.gasConsumption = msg.gasConsumption;

        send(SendParameters{
            to: msg.addr,
            bounce: false,
            value:  0,
            mode: SendRemainingValue | SendIgnoreErrors
        });

    }
    receive(msg: MsgSubStakeAddrWidthdwaw) {
        let ctx: Context = context();
        require(ctx.sender == self.master, "Invalid sender!");
        self.bExit=true;
        send(SendParameters{
            to: msg.addr,
            bounce: false,
            value:  myBalance() - context().value - self.minTonForStorage,
            mode: SendRemainingBalance | SendIgnoreErrors
        });
    }

    receive(msg: MsgSubStakeAddrDel) {
        require(self.bExit, "not exit");
        let ctx: Context = context();
        require(ctx.sender == self.master, "Invalid sender!");
        send(SendParameters{
            to: msg.addr,
            bounce: false,
            value: 0,
            mode: SendRemainingBalance | SendIgnoreErrors
        });
    }
}