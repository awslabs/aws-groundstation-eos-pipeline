# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import socket
import select
import os
import io

#   ---------------------------------------------
#   Misc Functions
#   ---------------------------------------------

def getBytesFromFile(fileName, msgSize):

    #   Reads and returns Bytes from filename in msgSize chunks

    f = open(fileName, "rb")
    while True:
        buffer = f.read(msgSize)
        if buffer:
            #for b in buffer:
            buffer.rstrip()
            yield buffer
        else:
            break

def RateLimited(maxPerSecond):

    #   Decorator function used to rate limit UDP packet sending

    minInterval = 1.0 / float(maxPerSecond)
    def decorate(func):
        lastTimeCalled = [0.0]
        def rateLimitedFunction(*args,**kargs):
            elapsed = time.time() - lastTimeCalled[0]
            leftToWait = minInterval - elapsed
            if leftToWait>0:
                time.sleep(leftToWait)
            ret = func(*args,**kargs)
            lastTimeCalled[0] = time.time()
            return ret
        return rateLimitedFunction
    return decorate

def appendToRawFile(outputFile, data):

    #   Writes received Bytes to outputFile

    #   Open file handle
    try:
        f = open(outputFile, "ab")
        num_bytes_written = f.write(data)

        #   Make sure the buffer is flushed correctly
        f.flush()
        os.fsync(f.fileno())
        return num_bytes_written
    except Exception as e:
        print(" (ERR) File open error: %s" % e )
        return 0

#   -------------------------------------------------------
#   Functions to send or receive & process UDP datagrams
#   -------------------------------------------------------

#   If rate limiting is required set maxPPS
#   and un-comment the decorator line '@RateLimited(maxPPS)'
maxPPS = 2000
#@RateLimited(maxPPS)
def sendDataFromFile(inFile, server, port, msgSize):

    bytesSent = 0

    #   Send buffer to UDP server
    #   rstrip() removes a newline char from the end if needed
    for b in getBytesFromFile(inFile, msgSize):
        sendUdpData(b.rstrip(), server, port)
        bytesSent += len(b.rstrip())

    return bytesSent

def extractVRTPayloadFromFile(inputFile, outputFile, packetSize):

    print("Extracting VRT payload from %s" % inputFile)
    packetNum = 0

    for message in getBytesFromFile(inputFile, packetSize):

        packetNum += 1;
        payloadLength = 0
        payload = extractVrtPayloadFromBin(message)
        payloadLength = len(payload)

        if payloadLength < 1:
            print("[%d] Packet not a valid VITA 49 format" % packetNum)

        else:
            print("[%d] Payload length: %d. Writing to file." % (packetNum, payloadLength) )
            appendToRawFile(outputFile, payload)

def sendUdpData(data, server, port):

    bytesToSend       = data
    serverAddressPort = (server, port)

    UDPClientSocket = socket.socket(family=socket.AF_INET, type=socket.SOCK_DGRAM)
    UDPClientSocket.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 3000000)
    UDPClientSocket.sendto(bytesToSend, serverAddressPort)
		# If data is in utf-8, convert to bytes inline
		# UDPClientSocket.sendto(bytes(MESSAGE, "utf-8"), serverAddressPort)

def startUdpListenerSimple(listenerPort, bufferSize, outputFile):

    #   Starts a UDP server and writes received data to a file, no packet processing

    localIP             = "127.0.0.1"
    numPacketsReceived  = 0
    numPacketsProcessed = 0
    totalDataSize       = 0
    inMemoryPayload     = b''
    inMemoryPayload = io.BytesIO(b'')
    outputMessageEveryNPackets = 1000

    try:
        UDPServerSocket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        #   Set the socket timeout to 120 seconds to trigger post-
        #   -processing after 2 mins of no data
        UDPServerSocket.settimeout(120)
        UDPServerSocket.bind((localIP, listenerPort))
        print("\nUDP server listening on %s:%s" % (localIP, listenerPort) )
    except Exception as e:

        if e.errno == 1:
            print(" (ERR) [ERROR_ROOT_REQUIRED] Socket open error: %s" % e )
        else:
            print(" (ERR) [ERROR_CANT_OPEN_SOCKET] Socket open error: %s" % e )
        return 0

    #   Open file handle
    try:
        f = open(outputFile, "wb")
    except Exception as e:
        print(" (ERR) File open error: %s" % e )
        return 0

    while(True):

        try:
            bytesAddressPair = UDPServerSocket.recvfrom(bufferSize)
            message          = bytesAddressPair[0]

            try:
                #   Option 1: Write received data to file
                #   Will cause packets to be dropped on a slow disk
                #f = open(outputFile, "wb+")
                #num_bytes_written = f.write(message)
                #f.flush()
                #os.fsync(f.fileno())
                #return num_bytes_written

                #   Test 2: Write unprocessed data to inMemoryBuffer (ByteIO Stream)
                #inMemoryPayload = inMemoryPayload + message
                #inMemoryPayload.write(message)

                #   Test 3: Extract VRT payload from the data then write data to ByteIO Stream (in-memory buffer)
                payload = extractVrtPayloadFromBin(message)
                inMemoryPayload.write(payload)

                #   Test 4: Extract VRT payload from the data then write data to file
                #payload = extractVrtPayloadFromBin(message)
                #inMemoryPayload.write(payload)

                if numPacketsReceived == 0:
                    #   Provide output for first packet only
                    print ("Received first packet. Size: %d Bytes" % (len(message)) )
                    print ("VRT Payload Size: %d Bytes" % (len(payload)) )

            except Exception as e:
                print(" (ERR) Packet processing error: %s" % e )
                break

            numPacketsReceived += 1

        except socket.timeout:
            #   No data received within the configured timeout period
            print ("Num Packets Received: %d" % (numPacketsReceived) )

            #   Get data from the BytesIO in-memory stream
            bufferData = inMemoryPayload.getvalue()
            totalBytesReceived = len(bufferData)
            if numPacketsReceived > 1 and totalBytesReceived > 0:

                #   Assume the transmission has finished
                #   Write received data to file
                try:
                    print("Writing memory buffer (%d Bytes) to output file..." % (totalBytesReceived) )
                    num_bytes_written = f.write(bufferData)

                    #   Make sure the buffer is flushed correctly
                    f.flush()
                    os.fsync(f.fileno())
                    f.close()

                    #   Clear the memory buffer
                    inMemoryPayload = b''

                    print("%d Bytes written to output file" % (num_bytes_written) )
                    exit()

                except Exception as e:
                    print("(ERR) File write error: %s" % e )
                    return 0


        except Exception as e:
            print("(ERR) Socket receive error: %s" % e )
            return 0

def startUdpListenerBin(listenerPort, bufferSize, outputFile):

    #   Starts a UDP server and writes received data to a file

    localIP             = "127.0.0.1"
    numPacketsReceived  = 0
    numPacketsProcessed = 0
    totalDataSize       = 0
    inMemoryPayload     = b''
    outputMessageEveryNPackets = 1000

    try:
        UDPServerSocket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        #   Set the socket timeout to 10 seconds
        UDPServerSocket.settimeout(10)
        #UDPServerSocket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 3000000)
        UDPServerSocket.bind((localIP, listenerPort))
        print("\nUDP server listening on %s:%s" % (localIP, listenerPort) )
        print("Output file: %s\n" % (outputFile))
    except Exception as e:

        if e.errno == 1:
            print(" (ERR) [ERROR_ROOT_REQUIRED] Socket open error: %s" % e )
        else:
            print(" (ERR) [ERROR_CANT_OPEN_SOCKET] Socket open error: %s" % e )
        return 0

    #   Open file handle
    try:
        f = open(outputFile, "wb", buffering=bufferSize)
    except Exception as e:
        print(" (ERR) File open error: %s" % e )
        return 0

    while(True):

        #   Read data into string
        try:
            bytesAddressPair = UDPServerSocket.recvfrom(bufferSize)

            message = bytesAddressPair[0]
            #address = str(bytesAddressPair[1][0])

            #appendToRawFile(outputFile, message)

            numPacketsReceived += 1

            payloadLength = 0
            payload = extractVrtPayloadFromBin(message)
            #   left to test if above function is causing the receive buffer issues
            #payload = message
            payloadLength = len(payload)

            if payloadLength < 1:
                print("[%d] Packet not a valid VITA 49 format" % numPacketsReceived)

            else:

                numPacketsProcessed += 1

                #   Add payload to inMemory payload chunk
                inMemoryPayload = inMemoryPayload + payload

                #   Print out message every 1000 packets
                #   If we print on ever packet STDOUT cant keep up
                #if numPacketsProcessed % outputMessageEveryNPackets == 0 or numPacketsReceived == 1:
                #    print("[%d] Receiving Data. Total payload %d Bytes" % (numPacketsReceived, len(inMemoryPayload)) )

        except socket.timeout:

            if len(inMemoryPayload) > 0:

                #   Write received data to file
                try:
                    print("Writing memory buffer to output file...")
                    #f = open(outputFile, "ab", buffering=8192)
                    num_bytes_written = f.write(inMemoryPayload)

                    #   Make sure the buffer is flushed correctly
                    f.flush()
                    os.fsync(f.fileno())

                    #   Clear the memory buffer
                    inMemoryPayload = b''

                    print("%d Payload Bytes written from %d packets" % (num_bytes_written, numPacketsProcessed) )
                    totalDataSize += num_bytes_written

                except Exception as e:
                    print("(ERR) File write error: %s" % e )
                    return 0

            print('')
            print('Status Update:')
            print(" %d packets received" % (numPacketsReceived))
            print(" %d packets processed successfully" % (numPacketsProcessed))
            print(" %d Total Bytes written to %s" % (totalDataSize, outputFile))

#   ---------------------------------------------
#   Functions to process VITA 49 data
#   ---------------------------------------------

def convertMaskAndTrimBytesToBitString(data, mask, rightShift, length):

    #   Performs multiple operations:
    #   1. Convert bytes to a Python integer bit string
    #   2. Mask values not needed
    #       e.g. 0b11111100 masked with 0b00001111 becomes 0b00001100
    #   3. Shift values we need to the right
    #       e.g. 0b00001100 shifted by 2 becomes 0b00000011
    #   4. Right-Trim the bit string to the desired length

    # Network / Big Endian format
    _BYTE_ORDER = r'big'

    try:
        #   1. Convert to int
        bytes = int.from_bytes(data, _BYTE_ORDER)
        #   2. Mask + 3 right-shift
        output = (bytes & mask) >> rightShift

        #   4. Right-Trim to the required length
        fmt = '0' + str(length) + 'b' # e.g. 04b / 08b
        output = format(output, fmt)

        return output

    except Exception as e:
        print(" (ERR) convertMaskAndTrimBytesToBitString error: %s" % e )
        return None

def checkForStreamId(data):

    streamIdIncluded = False

    #   We only want the first 4 bits, set other bits to zero, shift 4 places to the right, then trim to 4 in length
    binString = convertMaskAndTrimBytesToBitString(data, 0b11110000, 4, 4)
    if binString!=None:
        streamIdIncluded = binString == '0011' or binString == '0001' or binString == '0100' or binString == '0101'
    return [streamIdIncluded, binString]

def checkForClassId(data):

    classIdIncluded = False

    #   We only want bit 5, set the others to zeros and shift 3 places to the right, then trim length to 1
    binString = convertMaskAndTrimBytesToBitString(data, 0b00001000, 3, 1)
    classIdIncluded = binString == '1'

    return [classIdIncluded, binString]

def checkForTrailer(data):

    trailerIncluded = False

    #   We only want bit 6, set the others to zeros and shift 4 places to the right, then trim length to 1
    binString = convertMaskAndTrimBytesToBitString(data, 0b00000100, 4, 1)
    trailerIncluded = binString == '1'

    return [trailerIncluded, binString]

def checkForTimeStamp(data):

    timeStampIncluded = False

    #   We only want bits 1+2, set the others to zeros and shift 6 places to the right, then trim length to 1
    binString = convertMaskAndTrimBytesToBitString(data, 0b11000000, 6, 2)
    timeStampIncluded = binString != '10'

    return [timeStampIncluded, binString]

def extractVrtPayloadFromBin(udpData):

    #   Strips the VITA49 header and returns the payload data
    #   Expects VITA 49.2 AWS Uncoded Frame Data Format

    #   packet type       : first 4 bits of Byte 1 (streamIdIncluded)
    #   classIdIncluded   : bit 5 of Byte 1
    #   trailerIncluded   : bit 6 of Byte 1
    #   timeStampIncluded : first 2 bits of Byte 2

    #print("============================================")
    #print("Parsing VRT Header...")
    #print('')
    #print("  Byte 1: {:08b}".format(int.from_bytes(udpData[0:1], r'big')))
    #print("  Byte 2: {:08b}".format(int.from_bytes(udpData[1:2], r'big')))
    #print('')

    #   Check Byte 01 to see if StreamId is included
    streamIdIncluded = checkForStreamId(udpData[0:1])
    #print("  streamIdIncluded  : %s" % streamIdIncluded)

    #   Check Byte 01 to see if ClassId is included
    classIdIncluded = checkForClassId(udpData[0:1])
    #print("  classIdIncluded   : %s" % classIdIncluded)

    #   Check Byte 01 to see if a Trailer is included
    trailerIncluded = checkForTrailer(udpData[0:1])
    #print("  trailerIncluded   : %s" % trailerIncluded)

    #   Check Byte 02 to see if a TimeStamp is included
    timeStampIncluded = checkForTimeStamp(udpData[1:2])
    #print("  timeStampIncluded : %s" % (timeStampIncluded) )

    #   Calculate the length of the VITA 49 header based on the above fields
    vrtHeaderLength = 4 #   Min header length
    vrtHeaderLength += 4 if streamIdIncluded[0] else 0
    vrtHeaderLength += 8 if classIdIncluded[0] else 0
    vrtHeaderLength += 12 if timeStampIncluded[0] else 0
    #print("Processed packet. VRT Header Length : %d" % (vrtHeaderLength) )
    #print('')
    #print("============================================")

    #   Return the vrt payload only (skip the vrt header)
    return udpData[vrtHeaderLength:]
