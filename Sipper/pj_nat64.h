//
//  pj_nat64.h
//  Sipper
//
//  Created by Colin Morelli on 11/4/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#ifndef pj_nat64_h
#define pj_nat64_h

#import <pjsua.h>

/**
 * Options for NAT64 rewriting. Probably you want to enable all of them */
typedef enum nat64_options {
  /** Replace outgoing ipv6 with ipv4*/
  NAT64_REWRITE_OUTGOING_SDP          = 0x01,
  /** Replace incoming ipv4 with ipv6 */
  NAT64_REWRITE_INCOMING_SDP          = 0x02,
  /** Replace ipv4 address in 200 Ok for INVITE with ipv6 so ACK and BYE uses correct transport */
  NAT64_REWRITE_ROUTE_AND_CONTACT     = 0x04
} nat64_options;

/*
 * Enable nat64 rewriting module.
 * @param options       Bitmap of #nat64_options.
 *                      NAT64_REWRITE_OUTGOING_SDP | NAT64_REWRITE_INCOMING_SDP | NAT64_REWRITE_ROUTE_AND_CONTACT activates all options.
 * @default             0 - No nat64 rewriting is done.
 */
pj_status_t pj_nat64_enable_rewrite_module();

/*
 * Disable rewriting module, for instance when on a ipv4 network
 */
pj_status_t pj_nat64_disable_rewrite_module();

/*
 * Update rewriting options
 */
void pj_nat64_set_options(nat64_options options);

pj_status_t append_ipv4_ice_candidate(pj_pool_t *pool, pjmedia_sdp_session *session);

#endif /* pj_nat64_h */
