#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>

enum {
    kSMCUserClientOpen = 0,
    kSMCHandleYPCEvent = 2,
    kSMCReadKey = 5,
    kSMCWriteKey = 6,
    kSMCGetKeyInfo = 9,
};

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCKeyDataVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyDataPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
    uint8_t pad[3];
} SMCKeyDataKeyInfo;

typedef struct {
    uint32_t key;
    SMCKeyDataVersion vers;
    SMCKeyDataPLimitData pLimitData;
    SMCKeyDataKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParamStruct;

static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}

static void key_name(char *out, const char *fmt, int index) {
    snprintf(out, 5, fmt, index);
}

static kern_return_t smc_call(io_connect_t conn, SMCParamStruct *input, SMCParamStruct *output) {
    size_t out_size = sizeof(*output);
    return IOConnectCallStructMethod(
        conn,
        kSMCHandleYPCEvent,
        input,
        sizeof(*input),
        output,
        &out_size
    );
}

static int smc_key_info(io_connect_t conn, uint32_t key, SMCParamStruct *output) {
    SMCParamStruct input;
    memset(&input, 0, sizeof(input));
    memset(output, 0, sizeof(*output));
    input.key = key;
    input.data8 = kSMCGetKeyInfo;
    kern_return_t kr = smc_call(conn, &input, output);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    if (output->result != 0) {
        return output->result;
    }
    return 0;
}

static int smc_read(io_connect_t conn, uint32_t key, uint8_t *bytes, uint32_t *size, uint32_t *type) {
    SMCParamStruct info;
    int rc = smc_key_info(conn, key, &info);
    if (rc != 0) {
        return rc;
    }
    SMCParamStruct input;
    SMCParamStruct output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.keyInfo.dataSize = info.keyInfo.dataSize;
    input.data8 = kSMCReadKey;
    kern_return_t kr = smc_call(conn, &input, &output);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    if (output.result != 0) {
        return output.result;
    }
    uint32_t length = info.keyInfo.dataSize;
    if (length > 32) {
        length = 32;
    }
    memcpy(bytes, output.bytes, length);
    *size = length;
    *type = info.keyInfo.dataType;
    return 0;
}

static int smc_write(io_connect_t conn, uint32_t key, const uint8_t *bytes, uint32_t size) {
    SMCParamStruct info;
    int rc = smc_key_info(conn, key, &info);
    if (rc != 0) {
        return rc;
    }
    if (info.keyInfo.dataSize != size) {
        fprintf(stderr, "size mismatch for key write: expected %u got %u\n", info.keyInfo.dataSize, size);
        return -2;
    }
    SMCParamStruct input;
    SMCParamStruct output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.keyInfo.dataSize = size;
    input.data8 = kSMCWriteKey;
    memcpy(input.bytes, bytes, size);
    kern_return_t kr = smc_call(conn, &input, &output);
    if (kr != KERN_SUCCESS) {
        if ((uint32_t)kr == 0xE00002E2) {
            fprintf(stderr, "Permission denied. Run with sudo.\n");
        } else {
            fprintf(stderr, "IOConnectCallStructMethod failed: 0x%x\n", kr);
        }
        return -1;
    }
    if (output.result != 0) {
        return output.result;
    }
    return 0;
}

static const char *type_str(uint32_t type, char *buf) {
    buf[0] = (char)((type >> 24) & 0xFF);
    buf[1] = (char)((type >> 16) & 0xFF);
    buf[2] = (char)((type >> 8) & 0xFF);
    buf[3] = (char)(type & 0xFF);
    buf[4] = 0;
    return buf;
}

static int decode_rpm(const uint8_t *bytes, uint32_t size, uint32_t type) {
    char t[5];
    type_str(type, t);
    if (strcmp(t, "flt ") == 0 && size == 4) {
        float value;
        memcpy(&value, bytes, 4);
        return (int)(value + 0.5f);
    }
    if (strcmp(t, "fpe2") == 0 && size == 2) {
        uint16_t raw = ((uint16_t)bytes[0] << 8) | bytes[1];
        return (int)(raw / 4);
    }
    if (strcmp(t, "ui8 ") == 0 && size == 1) {
        return bytes[0];
    }
    return -1;
}

static int encode_rpm(int rpm, uint32_t type, uint32_t size, uint8_t *out) {
    char t[5];
    type_str(type, t);
    if (strcmp(t, "flt ") == 0 && size == 4) {
        float value = (float)rpm;
        memcpy(out, &value, 4);
        return 0;
    }
    if (strcmp(t, "fpe2") == 0 && size == 2) {
        uint16_t raw = (uint16_t)(rpm * 4);
        out[0] = (uint8_t)(raw >> 8);
        out[1] = (uint8_t)(raw & 0xFF);
        return 0;
    }
    fprintf(stderr, "unsupported RPM type '%s' size %u\n", t, size);
    return -1;
}

static int read_named_rpm(io_connect_t conn, const char *name) {
    uint8_t bytes[32];
    uint32_t size = 0;
    uint32_t type = 0;
    int rc = smc_read(conn, fourcc(name), bytes, &size, &type);
    if (rc != 0) {
        return -1;
    }
    return decode_rpm(bytes, size, type);
}

static int resolve_mode_key(io_connect_t conn, int index, char *out_name) {
    char upper[5];
    char lower[5];
    key_name(upper, "F%dMd", index);
    key_name(lower, "F%dmd", index);
    SMCParamStruct info;
    if (smc_key_info(conn, fourcc(upper), &info) == 0) {
        memcpy(out_name, upper, 5);
        return 0;
    }
    if (smc_key_info(conn, fourcc(lower), &info) == 0) {
        memcpy(out_name, lower, 5);
        return 0;
    }
    return -1;
}

static int set_manual_mode(io_connect_t conn, const char *mode_name) {
    uint8_t one = 1;
    int rc = smc_write(conn, fourcc(mode_name), &one, 1);
    if (rc == 0) {
        return 0;
    }
    if (rc != 0x82) {
        return rc;
    }
    SMCParamStruct info;
    if (smc_key_info(conn, fourcc("Ftst"), &info) != 0) {
        fprintf(stderr, "mode write rejected and Ftst is absent\n");
        return rc;
    }
    rc = smc_write(conn, fourcc("Ftst"), &one, 1);
    if (rc != 0) {
        fprintf(stderr, "Ftst unlock failed: 0x%x\n", rc);
        return rc;
    }
    for (int i = 0; i < 100; i++) {
        rc = smc_write(conn, fourcc(mode_name), &one, 1);
        if (rc == 0) {
            return 0;
        }
        if (rc != 0x82) {
            return rc;
        }
        usleep(100000);
    }
    fprintf(stderr, "Ftst unlock timed out for %s\n", mode_name);
    return 0x82;
}

static int set_fan_target(io_connect_t conn, int index, int rpm) {
    char mode_name[5];
    if (resolve_mode_key(conn, index, mode_name) != 0) {
        fprintf(stderr, "Fan %d: no mode key (F%dMd / F%dmd)\n", index, index, index);
        return -1;
    }
    int rc = set_manual_mode(conn, mode_name);
    if (rc != 0) {
        fprintf(stderr, "Fan %d: could not set manual mode on %s (0x%x)\n", index, mode_name, rc);
        return rc;
    }
    char target_name[5];
    key_name(target_name, "F%dTg", index);
    uint8_t bytes[32];
    uint32_t size = 0;
    uint32_t type = 0;
    rc = smc_read(conn, fourcc(target_name), bytes, &size, &type);
    if (rc != 0) {
        fprintf(stderr, "Fan %d: could not read %s (0x%x)\n", index, target_name, rc);
        return rc;
    }
    uint8_t encoded[32];
    memset(encoded, 0, sizeof(encoded));
    if (encode_rpm(rpm, type, size, encoded) != 0) {
        return -1;
    }
    rc = smc_write(conn, fourcc(target_name), encoded, size);
    if (rc != 0) {
        fprintf(stderr, "Fan %d: write %s failed (0x%x)\n", index, target_name, rc);
        return rc;
    }
    return 0;
}

static int restore_auto(io_connect_t conn, int index) {
    char mode_name[5];
    if (resolve_mode_key(conn, index, mode_name) != 0) {
        return -1;
    }
    uint8_t zero = 0;
    return smc_write(conn, fourcc(mode_name), &zero, 1);
}

static int list_fans(io_connect_t conn, int *count_out) {
    uint8_t bytes[32];
    uint32_t size = 0;
    uint32_t type = 0;
    int rc = smc_read(conn, fourcc("FNum"), bytes, &size, &type);
    if (rc != 0) {
        fprintf(stderr, "Could not read FNum (0x%x)\n", rc);
        return -1;
    }
    int count = decode_rpm(bytes, size, type);
    if (count_out) {
        *count_out = count;
    }
    printf("Fans: %d\n", count);
    for (int i = 0; i < count; i++) {
        char actual[5];
        char minn[5];
        char maxx[5];
        char tgt[5];
        key_name(actual, "F%dAc", i);
        key_name(minn, "F%dMn", i);
        key_name(maxx, "F%dMx", i);
        key_name(tgt, "F%dTg", i);
        printf(
            "Fan %d: actual=%d min=%d max=%d target=%d\n",
            i,
            read_named_rpm(conn, actual),
            read_named_rpm(conn, minn),
            read_named_rpm(conn, maxx),
            read_named_rpm(conn, tgt)
        );
    }
    return 0;
}

int main(int argc, char **argv) {
    const char *command = "list";
    if (argc > 1) {
        command = argv[1];
    }

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) {
        fprintf(stderr, "AppleSMC not found\n");
        return 2;
    }
    io_connect_t conn = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "IOServiceOpen failed: 0x%x\n", kr);
        return 2;
    }

    int status = 0;
    if (strcmp(command, "list") == 0) {
        status = list_fans(conn, NULL);
    } else if (strcmp(command, "max") == 0) {
        int count = 0;
        if (list_fans(conn, &count) != 0) {
            status = 2;
        } else {
            for (int i = 0; i < count; i++) {
                char maxx[5];
                key_name(maxx, "F%dMx", i);
                int max_rpm = read_named_rpm(conn, maxx);
                if (max_rpm <= 0) {
                    fprintf(stderr, "Fan %d: hardware max is %d; refusing\n", i, max_rpm);
                    status = 2;
                    break;
                }
                int rc = set_fan_target(conn, i, max_rpm);
                if (rc != 0) {
                    status = 2;
                    break;
                }
                printf("Fan %d: set to %d RPM (max)\n", i, max_rpm);
            }
            if (status == 0) {
                usleep(400000);
                printf("--- after ---\n");
                list_fans(conn, NULL);
            }
        }
    } else if (strcmp(command, "auto") == 0) {
        int count = 0;
        if (list_fans(conn, &count) != 0) {
            status = 2;
        } else {
            for (int i = 0; i < count; i++) {
                int rc = restore_auto(conn, i);
                if (rc != 0) {
                    fprintf(stderr, "Fan %d: auto restore failed (0x%x)\n", i, rc);
                    status = 2;
                } else {
                    printf("Fan %d: auto\n", i);
                }
            }
            uint8_t zero = 0;
            smc_write(conn, fourcc("Ftst"), &zero, 1);
        }
    } else {
        fprintf(stderr, "Usage: fanctl [list|max|auto]\n");
        status = 2;
    }

    IOServiceClose(conn);
    return status;
}
