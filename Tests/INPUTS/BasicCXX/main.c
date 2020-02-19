#include /*Object:include:main*/"Object.h"

int main(int argc, const char *argv[]) {
  struct Object *obj = newObject();
  return obj->field;
}
