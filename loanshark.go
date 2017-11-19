/*
Copyright IBM Corp. 2017 All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

		 http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"encoding/binary"
	"fmt"
	"strconv"

	"github.com/hyperledger/fabric/core/chaincode/shim"
	pb "github.com/hyperledger/fabric/protos/peer"
)

type loanManager struct {
	// Note: Do not save any state between invocations
	// All state should be persisted using the stub's ChaincodeStubInterface API
}

func (lm *loanManager) Init(stub shim.ChaincodeStubInterface) pb.Response {
	return shim.Success(nil)
}

func (lm *loanManager) Invoke(stub shim.ChaincodeStubInterface) pb.Response {
	function, args := stub.GetFunctionAndParameters()
	if function == "query" {
		if len(args) != 1 {
			return shim.Error("Expected 1 arg: <name>")
		}
		return shim.Success([]byte(fmt.Sprintf("%d", lm.query(stub, args[0]))))
	}

	if function != "loan" && function != "payback" {
		return shim.Error("Invalid function name. Expecting \"loan\" \"payack\" \"query\"")
	}

	if len(args) != 2 {
		return shim.Error("Expected 2 args: <name>, <amount>")
	}

	name := args[0]
	amount, err := strconv.ParseInt(args[1], 10, 64)
	if err != nil {
		return shim.Error(fmt.Sprintf("Amount should be an integer, got %s instead", args[1]))
	}
	if function == "loan" {
		return lm.loan(stub, name, int(amount))
	} else {
		return lm.payback(stub, name, int(amount))
	}
}

func (lm *loanManager) query(stub shim.ChaincodeStubInterface, name string) int {
	balance := 0
	rawBytes, err := stub.GetState(name)
	if err != nil {
		panic(err)
	}
	if rawBytes != nil {
		balance = int(binary.BigEndian.Uint64(rawBytes))
	}
	return balance
}

func (lm *loanManager) loan(stub shim.ChaincodeStubInterface, name string, amount int) pb.Response {
	loanedAmount := lm.query(stub, name)
	loanedAmount += amount
	return lm.put(stub, name, loanedAmount)
}

func (lm *loanManager) payback(stub shim.ChaincodeStubInterface, name string, amount int) pb.Response {
	loanedAmount := lm.query(stub, name)
	if loanedAmount < amount {
		return shim.Error(fmt.Sprintf("%s owns only %d, cannot repay %d", name, loanedAmount, amount))
	}
	loanedAmount -= amount
	return lm.put(stub, name, loanedAmount)
}

func (lm *loanManager) put(stub shim.ChaincodeStubInterface, name string, n int) pb.Response {
	rawBytes := make([]byte, 8)
	binary.BigEndian.PutUint64(rawBytes, uint64(n))
	err := stub.PutState(name, rawBytes)
	if err != nil {
		return shim.Error(fmt.Sprintf("Failed putting value into DB: %v", err))
	}
	return shim.Success(nil)
}

func main() {
	err := shim.Start(new(loanManager))
	if err != nil {
		fmt.Printf("Error starting chaincode: %s", err)
	}
}
