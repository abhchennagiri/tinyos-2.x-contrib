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
 * Blackbook Dictionary Boot Module
 *
 *  1. Start at the first valid sector of flash and 
 *     read nodes, documenting, deleting, etc.
 *
 *  2. Repeat step 1 for every sector.
 *
 *  3. After all nodes on all sectors have been accounted for,
 *     link the files and nodes together in the NodeBooter.
 * 
 *  4. Boot complete.
 *
 * @author David Moss - dmm@rincon.com
 */

#include "Blackbook.h"
#include "BlackbookConst.h"

module BBootDictionaryP {
  provides {
    interface BBoot;
  }
  
  uses {
    interface Boot;
    interface GenericCrc; 
    interface DirectStorage;
    interface VolumeSettings;
    interface EraseUnitMap;
    interface NodeBooter;
    interface NodeShop;
    interface NodeMap;
    interface State as CommandState;
    interface State as BlackbookState;
    interface BlackbookUtil;
  }
}

implementation {

  /** The current address we're scanning */
  uint32_t currentAddress;
  
  /** The current nodemeta_t being read from flash */
  nodemeta_t currentNodeMeta;
  
  /** The currently allocated flashnode_t from the NodeBooter */
  flashnode_t *currentNode;
  
  /** The currently allocated file_t from the NodeBooter */
  file_t *currentFile;
  
  /** The current sector index we're working with */
  uint8_t currentIndex;

  /** The current filename_t readd from flash */
  filename_t currentFilename;
  
  
  /** Command States */
  enum {
    S_IDLE_TWO = 0,
    S_READ_NODEMETA,
    S_READ_FILEMETA,
  };
  
  /***************** Prototypes ****************/
  /** Parse the newly read flashnode_t */
  task void parseCurrentNode();
  
  /** Allocate a new flashnode_t and read it in from the address "currentAddress" */
  task void getNewNode();
  
  /** Allocate a new file_t and read it in from the address "currentAddress" */
  task void getNewFile();
  
  /** Read the nodemeta_t for the flashnode_t at the address "currentAddress" */
  task void readNodeMeta();
  
  /** Read the filemeta_t for the flashnode_t at the address "currentAddress" */
  task void readFileMeta();
 
  /** Continue parsing through the flash */
  task void continueParsing();



  /***************** BBoot Commands ****************/
  /**
   * @return TRUE if the file_t system has booted
   */
  command bool BBoot.isBooted() {
    return call BlackbookState.getState() != S_BOOT_BUSY;
  }
  
  
  /***************** Boot Events ****************/
  /**
   * Signaled when the flash is ready to be used
   * @param error - SUCCESS if we can use the flash.
   */
  event void Boot.booted() {
    call BlackbookState.forceState(S_BOOT_BUSY);
    currentIndex = 0;
    post continueParsing();
  }
  
  
  /***************** DirectStorage Events ****************/
  /**
   * Read is complete
   * @param addr - the address to read from
   * @param *buf - the buffer to read into
   * @param len - the amount to read
   * @return SUCCESS if the bytes will be read
   */
  event void DirectStorage.readDone(uint32_t addr, void *buf, uint32_t len, error_t error) {
    if(call CommandState.getState() == S_READ_NODEMETA) {
      if(error) {
        post readNodeMeta();
        return;
      }

      if(currentNodeMeta.magicNumber != META_INVALID && currentNodeMeta.fileElement == 0) {
        post getNewFile();
        return;
        
      } else {
        post parseCurrentNode(); 
      }
      
    } else if(call CommandState.getState() == S_READ_FILEMETA) {
      if(error) {
        post readFileMeta();
        return;
      }
      
      currentFile->filenameCrc = call GenericCrc.crc16(0, &currentFilename, sizeof(filename_t));
      currentFile->firstNode = currentNode;
      
      post parseCurrentNode();
    }
  }
  
  /**
   * Write is complete
   * @param addr - the address to write to
   * @param *buf - the buffer to write from
   * @param len - the amount to write
   * @return SUCCESS if the bytes will be written
   */
  event void DirectStorage.writeDone(uint32_t addr, void *buf, uint32_t len, error_t error) {
  }
  
  /**
   * Erase is complete
   * @param sector - the sector id to erase
   * @return SUCCESS if the sector will be erased
   */
  event void DirectStorage.eraseDone(uint16_t sector, error_t error) {
  }
  
  /**
   * Flush is complete
   * @param error - SUCCESS if the flash was flushed
   */
  event void DirectStorage.flushDone(error_t error) {
  }
  
  /**
   * CRC-16 is computed
   * @param crc - the computed CRC.
   * @param addr - the address to start the CRC computation
   * @param len - the amount of data to obtain the CRC for
   * @return SUCCESS if the CRC will be computed.
   */
  event void DirectStorage.crcDone(uint16_t calculatedCrc, uint32_t addr, uint32_t len, error_t error) {
  }

  
  /***************** NodeShop Events ****************/
  /** 
   * The node's metadata was written to flash
   * @param focusedNode - the flashnode_t that metadata was written for
   * @param error - SUCCESS if it was written
   */
  event void NodeShop.metaWritten(flashnode_t *focusedNode, error_t error) {
  }
  
  /**
   * The filename_t was retrieved from flash
   * @param focusedFile - the file_t that we obtained the filename_t for
   * @param *name - pointer to where the filename_t was stored
   * @param error - SUCCESS if the filename_t was retrieved
   */
  event void NodeShop.filenameRetrieved(file_t *focusedFile, filename_t *name, error_t error) {
  }
  
  /**
   * A flashnode_t was deleted from flash by marking its magic number
   * invalid in the metadata.
   * @param focusedNode - the flashnode_t that was deleted.
   * @param error - SUCCESS if the flashnode_t was deleted successfully.
   */
  event void NodeShop.metaDeleted(flashnode_t *focusedNode, error_t error) {
    currentNode->nodestate = NODE_EMPTY;
    if(currentFile != NULL) {
      currentFile->filestate = FILE_EMPTY;   
    }
    post continueParsing();
  }
 
  /**
   * A crc was calculated from flashnode_t data on flash
   * @param dataCrc - the crc of the data read from the flashnode_t on flash.
   * @param error - SUCCESS if the crc is valid
   */
  event void NodeShop.crcCalculated(uint16_t dataCrc, error_t error) {
  }
  
  /***************** Tasks ****************/
  /**
   * Parse the current flashnode_t and nodemeta_t
   */
  task void parseCurrentNode() {
    currentNode->fileElement = currentNodeMeta.fileElement;
    currentNode->filenameCrc = currentNodeMeta.filenameCrc;
    currentNode->reserveLength = currentNodeMeta.reserveLength;

    // Dictionary files use all their reserved length:
    currentNode->dataLength = currentNodeMeta.reserveLength;
    
    if(currentNodeMeta.magicNumber == META_EMPTY) {
      // Advance to the next sector.
      currentNode->nodestate = NODE_EMPTY;
      if(currentFile != NULL) {
        currentFile->filestate = FILE_EMPTY;
      }
      
      currentIndex++;
      post continueParsing();
      return;
      
    } else if(currentNodeMeta.magicNumber == META_CONSTRUCTING) {
      /*
       * This flashnode_t must be deleted. 
       * First we act like it's there, then we delete it.
       */
      currentNode->nodestate = NODE_VALID;
      call EraseUnitMap.documentNode(currentNode);
      call NodeShop.deleteNode(currentNode);
      return;
        
    } else if(currentNodeMeta.magicNumber == META_VALID) {
      currentNode->nodestate = NODE_BOOTING;
      if(currentFile != NULL) {
        currentFile->filestate = FILE_IDLE;
      }
      
      if(call NodeMap.hasDuplicate(currentNode)) {
        call NodeShop.deleteNode(currentNode);
        return; 
      } else {
        call EraseUnitMap.documentNode(currentNode);
      }
      
    } else if(currentNodeMeta.magicNumber == META_INVALID) {
      currentNode->nodestate = NODE_DELETED;
      if(currentFile != NULL) {
        currentFile->filestate = FILE_EMPTY;
      }
      call EraseUnitMap.documentNode(currentNode);
      currentNode->nodestate = NODE_EMPTY;
      
    } else {
      // Garbage found. Document, delete, and advance to the next page.
      currentNode->nodestate = NODE_DELETED;
      currentNode->flashAddress = currentAddress;
      currentNode->reserveLength = 1;
      currentNode->dataLength = 1;
      call EraseUnitMap.documentNode(currentNode);
      currentNode->nodestate = NODE_EMPTY;
      if(currentFile != NULL) {
        currentFile->filestate = FILE_EMPTY;
      }
    }
    
    post continueParsing();
  }
  
  
  /**
   * Controls the state of the boot loop
   * and verifies the currentAddress is within range
   */
  task void continueParsing() {
    if(currentIndex < call EraseUnitMap.getTotalEraseBlocks()) {
      // Ensure the current address is not at the next sector's base address
      if((currentAddress = call EraseUnitMap.getEraseBlockWriteAddress(call EraseUnitMap.getEraseBlock(currentIndex))) 
          < call EraseUnitMap.getNextEraseBlockAddress(call EraseUnitMap.getEraseBlock(currentIndex))) {
        post getNewNode();
      
      } else {
        // Reached the end of the sector
        currentIndex++;
        post continueParsing();
      }
      
    } else {
      // Done loading nodes. Link, and finish booting.  Dictionary-only functionality
      // requires no checkpoint
      call NodeBooter.link();
      call CommandState.toIdle();
      call BlackbookState.toIdle();
      signal BBoot.booted(call NodeMap.getTotalNodes(), call NodeMap.getTotalFiles(), SUCCESS);
    }
  }
  
  /**
   * Allocate a new flashnode_t and read it in from the address "currentAddress"
   */
  task void getNewNode() {
    currentFile = NULL;
    if((currentNode = call NodeBooter.requestAddNode()) == NULL) {
      // There aren't enough nodes in our NodeMap. Do not change
      //  the BlackbookState to prevent the file_t system from being
      //  further corrupted.
      signal BBoot.booted(call NodeMap.getTotalNodes(), call NodeMap.getTotalFiles(), FAIL);
      return;
    }
   
    post readNodeMeta();
  }

  
  /**
   * Allocate a new file_t and read it in from the address "currentAddress"
   */
  task void getNewFile() {
    if((currentFile = call NodeBooter.requestAddFile()) == NULL) {
      // Massive error: There aren't enough nodes in our NodeMap
      //  to supply the amount of nodes on flash. Do not change
      //  the BlackbookState to prevent the file_t system from being
      //  corrupted.
      signal BBoot.booted(call NodeMap.getTotalNodes(), call NodeMap.getTotalFiles(), FAIL);
      return;
    }
    
    currentFile->firstNode = currentNode;
    post readFileMeta(); 
  }
  
  /**
   * Read the nodemeta_t from the flashnode_t at the flash address "currentAddress"
   */
  task void readNodeMeta() {
    call CommandState.forceState(S_READ_NODEMETA);
    currentNode->flashAddress = currentAddress;
    if(call DirectStorage.read(currentAddress, &currentNodeMeta, sizeof(nodemeta_t)) != SUCCESS) {
      post readNodeMeta();
    }
  }
  
  /** 
   * Read the filemeta_t for the flashnode_t at the flash address "currentAddress"
   * into the currentFile
   */
  task void readFileMeta() {
    call CommandState.forceState(S_READ_FILEMETA);
    if(call DirectStorage.read(currentAddress + sizeof(nodemeta_t), &currentFilename, sizeof(filemeta_t)) != SUCCESS) {
      post readFileMeta();
    }
  }
}


