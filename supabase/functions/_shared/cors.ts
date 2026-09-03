// `*` je tu sprejemljivo: vsi odjemalci teh funkcij so mobilna aplikacija,
// ki Origin sploh ne poslje, in kjer `verify_jwt = true` velja, brskalnik
// brez veljavnega zetona nicesar ne dosezi. Ce kdaj pride spletni
// odjemalec, to zozi na njegovo domeno.
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
