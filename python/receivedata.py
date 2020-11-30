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

import awsgs
import time
import os
import sys

#satelliteName = 'aqua'
bufferSize    = 409600
listenerPort  = 50000

#   Set the output fileName
if len(sys.argv) < 2:
    timestr = time.strftime("%Y%m%d-%H%M")
    outputFile = timestr + '-' + 'noname' + '-raw.bin'
else:
    outputFile=sys.argv[1]

#logFile = outputFile + '.log'

print("\nRemoving previous output file (%s) if exists" % outputFile)
if os.path.isfile(outputFile):
    os.remove(outputFile)

#   Capture and process binary data from a direct broadcast stream
#awsgs.startTwistedUdpListener(listenerPort, '127.0.0.1')
#awsgs.startUdpListenerBin(listenerPort, bufferSize, outputFile)
awsgs.startUdpListenerSimple(listenerPort, bufferSize, outputFile)
