#include "include/pcm_to_ogg/pcm_to_ogg_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>

#include "pcm_to_ogg_plugin_private.h"

// Force linking of FFI symbols from pcm_to_ogg_library
// This ensures the symbols are included in the shared library
extern "C" {
  // Forward declaration for OggOutput struct
  struct OggOutput;
  typedef struct OggOutput OggOutput;
  
  // Non-streaming encoding functions
  void* encode_pcm_to_ogg(float*, long, int, long, float);
  void free_ogg_output(OggOutput*);
  
  // Streaming encoding functions
  void* create_ogg_encoder(int, long, float);
  OggOutput* encode_pcm_chunk(void*, float*, long);
  OggOutput* finish_encoding(void*);
  void destroy_ogg_encoder(void*);
  
  // Keep references to ensure linking (will be optimized away but forces symbol inclusion)
  static void* _dummy_refs __attribute__((used)) = (void*[]){
    (void*)encode_pcm_to_ogg,
    (void*)free_ogg_output,
    (void*)create_ogg_encoder,
    (void*)encode_pcm_chunk,
    (void*)finish_encoding,
    (void*)destroy_ogg_encoder,
  };
}

#define PCM_TO_OGG_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), pcm_to_ogg_plugin_get_type(), \
                              PcmToOggPlugin))

struct _PcmToOggPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(PcmToOggPlugin, pcm_to_ogg_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void pcm_to_ogg_plugin_handle_method_call(
    PcmToOggPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version();
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

FlMethodResponse* get_platform_version() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void pcm_to_ogg_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(pcm_to_ogg_plugin_parent_class)->dispose(object);
}

static void pcm_to_ogg_plugin_class_init(PcmToOggPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = pcm_to_ogg_plugin_dispose;
}

static void pcm_to_ogg_plugin_init(PcmToOggPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  PcmToOggPlugin* plugin = PCM_TO_OGG_PLUGIN(user_data);
  pcm_to_ogg_plugin_handle_method_call(plugin, method_call);
}

void pcm_to_ogg_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  PcmToOggPlugin* plugin = PCM_TO_OGG_PLUGIN(
      g_object_new(pcm_to_ogg_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "pcm_to_ogg",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
