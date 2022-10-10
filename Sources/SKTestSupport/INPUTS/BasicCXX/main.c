#include /*Object:include:main*/"Object.h"

int main(int argc, const char *argv[]) {
  struct /*Object:ref:main*/Object *obj = /*Object:ref:newObject*/newObject();
  return obj->field;
}
