/**
 * Interface to platform specific functions
 * 
 * */ 
interface DsnPlatform {
	command void init();
	async command void flushUart();
	async event void rxRequest();
	async command void rxGrant();
	async command void rxRelease();
	command am_addr_t getSavedId();
	command void setNodeId(am_addr_t id);
	command void* getHeader( message_t* msg );
	command uint8_t getHeaderLength();
	command uint8_t getPayloadLength(message_t * msg);
	async command bool isHandshake();
}