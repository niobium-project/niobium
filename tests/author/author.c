/* Independent C consumer: public descriptors construct the same typed reference product. */
#include <niobium/compiler.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static nbc2_builder *builder;
static nbc2_view view(const char *s) { return (nbc2_view){(const uint8_t *)s,strlen(s)}; }
static void check(int32_t result) {
 if (!result) return;
 nbc2_view error={0}; nbc2_last_error(builder,&error);
 fprintf(stderr,"authoring %d: %.*s\n",result,(int)error.len,error.data);
 exit(1);
}
static nbc2_object value(nbc2_value_desc d) {
 nbc2_object object={0}; check(nbc2_value(builder,&d,&object)); return object;
}
static nbc2_object binding(nbc2_binding_desc d) {
 nbc2_object object={0}; check(nbc2_binding(builder,&d,&object)); return object;
}
static nbc2_object literal(nbc2_object v) {
 return binding((nbc2_binding_desc){.tag=NBC2_LITERAL,.payload=v});
}
static nbc2_object text(const char *s) {
 return literal(value((nbc2_value_desc){.tag=NBC2_TEXT,.text=view(s)}));
}
int main(int argc,char **argv) {
 if(argc!=4&&argc!=5) return 2;
 nbc2_requirement requirements[]={{view("content.tree"),1},{view("machine.facts"),1}};
 nbc2_profile profile={view("niobium.user.component"),view(argc==5?argv[4]:"aarch64-macos"),{requirements,2}};
 check(nbc2_create(2,view("reference"),1,1,&profile,&builder));
 check(nbc2_root(builder,view("application"),1));
 check(nbc2_state_root(builder,view("application")));
 nbc2_library library={.id=view("tools"),.member=view("libs/tools.wasm"),
  .sha256=view(argv[2]),.bytes=strtoull(argv[3],NULL,10)};
 check(nbc2_library_add(builder,&library));
 check(nbc2_input(builder,view("enabled"),value((nbc2_value_desc){.tag=NBC2_BOOL,.flags=1})));
 check(nbc2_input(builder,view("label"),value((nbc2_value_desc){.tag=NBC2_TEXT,.text=view("Toolchain")})));
 nbc2_grant grant={.id=view("owned"),.root=view("application"),.primitive=requirements[0],
  .max_entries=64,.max_bytes=1<<20,.file_access={1,3,1},.directory_access={2,3,1}};
 check(nbc2_grant_add(builder,&grant));
 uint8_t zeros[32]={0};
 nbc2_named fields[]={
  {view("format"),value((nbc2_value_desc){.tag=NBC2_ENUM,.text=view("posix-pax-v1")})},
  {view("sha256"),value((nbc2_value_desc){.tag=NBC2_BYTES,.text={zeros,32}})},
  {view("bytes"),value((nbc2_value_desc){.tag=NBC2_U64,.unsigned_value=10240})}
 };
 nbc2_object reference=value((nbc2_value_desc){.tag=NBC2_RECORD,.fields={fields,3}});
 nbc2_view os=view("os");
 nbc2_named request[]={
  {view("root"),text("application")},{view("grant"),text("owned")},
  {view("prefix"),text("toolchain")},{view("content"),literal(reference)},
  {view("label"),binding((nbc2_binding_desc){.tag=NBC2_INPUT,.reference=view("label")})},
  {view("platform"),binding((nbc2_binding_desc){.tag=NBC2_OBSERVATION,
   .reference=view("machine"),.projection={&os,1}})},
  {view("enabled"),binding((nbc2_binding_desc){.tag=NBC2_INPUT,.reference=view("enabled")})},
  {view("previous"),binding((nbc2_binding_desc){.tag=NBC2_PREVIOUS_STATE})}
 };
 nbc2_object argument=binding((nbc2_binding_desc){.tag=NBC2_RECORD_BINDING,.fields={request,8}});
 nbc2_view grant_id=view("owned");
 nbc2_observation machine={.id=view("machine"),.function=view("facts"),.primitive=requirements[1]};
 check(nbc2_observe(builder,&machine));
 nbc2_call call={.id=view("configure"),.library=view("tools"),
  .interface_name=view("niobium:reference/installer@1.0.0"),.function=view("build"),
  .arguments={&argument,1},.grants={&grant_id,1},.state_version=1,.result_role=1};
 check(nbc2_call_add(builder,&call));
 nbc2_buffer buffer={0};check(nbc2_emit(builder,&buffer));nbc2_destroy(builder);
 FILE *out=fopen(argv[1],"wbx");if(!out)return 1;
 size_t written=fwrite(buffer.data,1,buffer.len,out);int closed=fclose(out);
 int success=written==buffer.len&&closed==0;nbc2_buffer_free(&buffer);return success?0:1;
}
